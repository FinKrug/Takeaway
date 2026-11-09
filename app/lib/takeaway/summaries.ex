defmodule Takeaway.Summaries do
  @moduledoc """
  Post-speech summaries, generated once after a speech ends and cached in the
  `summaries` table.

    * speaker summary (one per speech) - content map with `"summary"`,
      `"question_groups"` (`%{"label", "count", "questions"}`),
      `"question_spikes"` (`%{"start_ms", "end_ms", "count"}`),
      `"total_questions"` and `"has_transcript"`.
    * attendee summary (one per speech and user) - content map with
      `"cliffnotes"` (the speech's cliffnotes merged with the attendee's own
      notes), `"notes"` (their raw notes) and `"has_transcript"`.

  Prose comes from `Takeaway.LLM`; when it is not configured or fails, a plain
  extractive fallback is used so a summary always exists. Question grouping and
  spike detection are computed locally and never depend on the LLM. Speeches
  without a transcript or without questions produce a summary that says so.
  """
  import Ecto.Query

  alias Takeaway.{Billing, LLM, Notes, Questions, Repo, Transcripts}
  alias Takeaway.Speeches.Speech
  alias Takeaway.Summaries.Summary

  @max_transcript_chars 12_000
  @top_groups 5
  @buckets 10
  @top_spikes 3

  def topic(speech_id), do: "speech:#{speech_id}:summary"
  def subscribe(speech_id), do: Phoenix.PubSub.subscribe(Takeaway.PubSub, topic(speech_id))

  @doc "The cached speaker summary, or nil."
  def get_speaker_summary(speech_id),
    do: Repo.one(from s in Summary, where: s.speech_id == ^speech_id and s.kind == "speaker")

  @doc "The cached summary for one attendee, or nil."
  def get_attendee_summary(speech_id, user_id),
    do:
      Repo.one(
        from s in Summary,
          where: s.speech_id == ^speech_id and s.kind == "attendee" and s.user_id == ^user_id
      )

  @doc "Whether the speech's plan includes summaries."
  def allowed?(%Speech{} = speech), do: Billing.speech_feature_allowed?(speech, :summaries)

  @doc """
  Returns the cached speaker summary, generating and caching it on first call.
  Returns `{:error, :not_ended}` while the speech is still running and
  `{:error, :plan_required}` when the speech's plan does not include summaries.
  """
  def speaker_summary(%Speech{ended_at: nil}), do: {:error, :not_ended}

  def speaker_summary(%Speech{} = speech) do
    if allowed?(speech) do
      case get_speaker_summary(speech.id) do
        %Summary{} = cached -> {:ok, cached}
        nil -> generate_speaker(speech)
      end
    else
      {:error, :plan_required}
    end
  end

  @doc "Like `speaker_summary/1` for one attendee."
  def attendee_summary(%Speech{ended_at: nil}, _user_id), do: {:error, :not_ended}

  def attendee_summary(%Speech{} = speech, user_id) do
    if allowed?(speech) do
      case get_attendee_summary(speech.id, user_id) do
        %Summary{} = cached -> {:ok, cached}
        nil -> generate_attendee(speech, user_id)
      end
    else
      {:error, :plan_required}
    end
  end

  @doc "Generates the speaker summary (if missing) and broadcasts `{:summary_ready, speech_id}`."
  def generate_on_end(%Speech{} = speech) do
    result = speaker_summary(speech)
    Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech.id), {:summary_ready, speech.id})
    result
  end

  # -- generation -------------------------------------------------------------

  defp generate_speaker(speech) do
    segments = Transcripts.list_segments(speech.id)
    questions = Questions.list_questions(speech.id)
    transcript = transcript_text(segments)

    {summary, source} = speaker_prose(speech, transcript, questions)

    content = %{
      "summary" => summary,
      "question_groups" => question_groups(questions),
      "question_spikes" => question_spikes(speech, questions, segments),
      "total_questions" => length(questions),
      "has_transcript" => transcript != ""
    }

    store(%{kind: "speaker", speech_id: speech.id}, {content, source}, fn ->
      get_speaker_summary(speech.id)
    end)
  end

  defp generate_attendee(speech, user_id) do
    transcript = speech.id |> Transcripts.list_segments() |> transcript_text()

    notes =
      speech.id |> Notes.list_notes(user_id) |> Enum.map(& &1.body) |> Enum.reject(&blank?/1)

    {cliffnotes, source} = attendee_prose(speech, transcript, notes)

    content = %{
      "cliffnotes" => cliffnotes,
      "notes" => notes,
      "has_transcript" => transcript != ""
    }

    store(%{kind: "attendee", speech_id: speech.id, user_id: user_id}, {content, source}, fn ->
      get_attendee_summary(speech.id, user_id)
    end)
  end

  # Insert; if a concurrent caller won the race, return their row instead.
  defp store(attrs, {content, generated_by}, fetch) do
    attrs = Map.merge(attrs, %{content: content, generated_by: generated_by})

    with {:ok, _} <-
           %Summary{}
           |> Summary.changeset(attrs)
           |> Repo.insert(on_conflict: :nothing) do
      {:ok, fetch.()}
    end
  end

  # -- prose ------------------------------------------------------------------

  defp speaker_prose(speech, transcript, questions) do
    cond do
      transcript == "" and questions == [] ->
        {"No transcript was recorded and no questions were asked, so there is nothing to summarize.",
         "none"}

      true ->
        prompt = """
        Speech title: #{speech.title}
        Description: #{speech.description || "(none)"}

        Transcript:
        #{if transcript == "", do: "(no transcript was recorded)", else: transcript}

        Audience questions:
        #{if questions == [], do: "(none)", else: Enum.map_join(questions, "\n", &"- #{&1.text}")}
        """

        llm(
          "You write short post-talk summaries for the speaker. In 3-5 sentences cover the main points of the talk and what the audience asked about. Plain text, no markdown. Do not invent content that is not in the input.",
          prompt,
          fallback_speaker(transcript, questions)
        )
    end
  end

  defp attendee_prose(speech, transcript, notes) do
    if transcript == "" and notes == [] do
      {"No transcript was recorded for this speech and you did not take any notes.", "none"}
    else
      prompt = """
      Speech title: #{speech.title}

      Transcript:
      #{if transcript == "", do: "(no transcript was recorded)", else: transcript}

      The attendee's own notes:
      #{if notes == [], do: "(none)", else: Enum.map_join(notes, "\n---\n", & &1)}
      """

      llm(
        "You write cliffnotes for an attendee after a talk: a concise bullet list of the key takeaways, merging the speech content with the attendee's own notes (keep their points and mark them with 'You noted:'). Plain text, one bullet per line starting with '- '. Do not invent content that is not in the input.",
        prompt,
        fallback_attendee(transcript)
      )
    end
  end

  defp llm(system, prompt, fallback) do
    case LLM.complete(system, prompt) do
      {:ok, text} -> {text, LLM.name()}
      {:error, _} -> {fallback, "extractive"}
    end
  end

  defp fallback_speaker(transcript, questions) do
    talk =
      if transcript == "",
        do: "No transcript was recorded for this speech.",
        else: "Talk excerpt: " <> excerpt(transcript)

    asked =
      case questions do
        [] -> "No questions were asked."
        qs -> "#{length(qs)} question(s) were asked."
      end

    talk <> " " <> asked
  end

  defp fallback_attendee(""), do: "No transcript was recorded for this speech."

  defp fallback_attendee(transcript), do: "Talk excerpt: " <> excerpt(transcript)

  defp excerpt(text) do
    if String.length(text) > 600, do: String.slice(text, 0, 600) <> "...", else: text
  end

  defp transcript_text(segments) do
    segments
    |> Enum.map_join(" ", & &1.text)
    |> String.trim()
    |> String.slice(0, @max_transcript_chars)
  end

  # -- question analytics -----------------------------------------------------

  @doc false
  def question_groups(questions) do
    questions
    |> Enum.group_by(fn q -> q.group_id || {:single, q.id} end)
    |> Enum.map(fn {_key, [first | _] = qs} ->
      %{"label" => first.text, "count" => length(qs), "questions" => Enum.map(qs, & &1.text)}
    end)
    |> Enum.sort_by(&{-&1["count"], &1["label"]})
    |> Enum.take(@top_groups)
  end

  @doc """
  Splits the talk into equal time buckets and returns the busiest ones (at
  least 2 questions), in talk order.
  """
  def question_spikes(_speech, [], _segments), do: []

  def question_spikes(speech, questions, segments) do
    max_offset = questions |> Enum.map(& &1.offset_ms) |> Enum.max()
    max_seg = segments |> Enum.map(& &1.end_ms) |> Enum.max(fn -> 0 end)

    from_clock =
      if speech.started_at && speech.ended_at,
        do: DateTime.diff(speech.ended_at, speech.started_at, :millisecond),
        else: 0

    duration = Enum.max([max_offset + 1, max_seg, from_clock])
    size = max(div(duration + @buckets - 1, @buckets), 1)

    questions
    |> Enum.frequencies_by(&div(&1.offset_ms, size))
    |> Enum.filter(fn {_, n} -> n >= 2 end)
    |> Enum.sort_by(fn {i, n} -> {-n, i} end)
    |> Enum.take(@top_spikes)
    |> Enum.sort()
    |> Enum.map(fn {i, n} ->
      %{"start_ms" => i * size, "end_ms" => (i + 1) * size, "count" => n}
    end)
  end

  defp blank?(s), do: String.trim(s || "") == ""
end
