defmodule Takeaway.Questions do
  @moduledoc "Questions asked by users during a speech."
  import Ecto.Query
  alias Takeaway.Accounts.User
  alias Takeaway.Questions.Question
  alias Takeaway.Speeches.Speech
  alias Takeaway.Repo

  @doc "Lists a speech's questions in speech order. Retracted ones are excluded unless `include_retracted: true`."
  def list_questions(speech_id, opts \\ []) do
    query =
      from q in Question,
        where: q.speech_id == ^speech_id,
        order_by: [asc: q.offset_ms, asc: q.id]

    if Keyword.get(opts, :include_retracted, false),
      do: Repo.all(query),
      else: Repo.all(where(query, [q], is_nil(q.retracted_at)))
  end

  @doc "Ranked active question groups, including singleton questions awaiting grouping."
  def list_top_groups(speech_id, opts \\ []) do
    speech_id
    |> list_questions()
    |> Enum.group_by(fn q ->
      if q.group_id, do: "group-#{q.group_id}", else: "question-#{q.id}"
    end)
    |> Enum.map(fn {id, questions} ->
      first = Enum.min_by(questions, & &1.id)

      %{
        id: id,
        text: first.text,
        count: length(questions),
        questions: Enum.map(questions, & &1.text)
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.text, &1.id})
    |> Enum.take(Keyword.get(opts, :limit, 10))
  end

  @doc "PubSub topic for a speech's question events."
  def topic(speech_id), do: "speech:#{speech_id}:questions"

  @doc "Global PubSub topic for all question events across speeches."
  def global_topic, do: "questions:all"

  def subscribe(speech_id), do: Phoenix.PubSub.subscribe(Takeaway.PubSub, topic(speech_id))

  @doc "Subscribes to global question events across all speeches."
  def subscribe_global, do: Phoenix.PubSub.subscribe(Takeaway.PubSub, global_topic())

  @doc """
  Submits a question from `user` to `speech`, stamped with the offset from the speech start
  (0 if not started). Runs the filter hook first (see `filter_text/1`); on success broadcasts
  `{:question_created, question}` on `speech:<id>`.
  """
  def submit_question(%Speech{} = speech, %User{} = user, attrs, now \\ DateTime.utc_now()) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    text = attrs["text"] |> to_string() |> String.trim()

    with {:ok, text} <- filter_text(text),
         {:ok, question} <-
           create_question(%{
             "text" => text,
             "slide_number" => attrs["slide_number"],
             "offset_ms" => offset_ms(speech, now),
             "user_id" => user.id,
             "speech_id" => speech.id
           }) do
      # Only local data is used here; Elasticsearch enrichment runs off the request path.
      question = Takeaway.Questions.Tagging.attach_current(question, speech)
      broadcast(speech.id, {:question_created, question})
      {:ok, question}
    end
  end

  @doc """
  Retracts a question, only if `user` asked it. Broadcasts `{:question_retracted, question}`.
  Returns `{:error, :not_found}` or `{:error, :forbidden}`.
  """
  def retract_question_by(question_id, %User{} = user) do
    case get_question(question_id) do
      nil ->
        {:error, :not_found}

      %Question{user_id: uid} when uid != user.id ->
        {:error, :forbidden}

      %Question{retracted_at: at} = q when not is_nil(at) ->
        {:ok, q}

      question ->
        with {:ok, question} <- retract_question(question) do
          broadcast(question.speech_id, {:question_retracted, question})
          {:ok, question}
        end
    end
  end

  @doc """
  Filter hook run before saving. Configure `config :takeaway, :question_filter` with a
  1-arity function or `{module, function}` returning `{:ok, text}` or `{:error, reason}`.
  Defaults to `Takeaway.Questions.Filter.filter/1` (question and profanity checks).
  """
  def filter_text(text) do
    case Application.get_env(:takeaway, :question_filter) do
      nil -> Takeaway.Questions.Filter.filter(text)
      fun when is_function(fun, 1) -> fun.(text)
      {m, f} -> apply(m, f, [text])
    end
  end

  # Words that open a question on their own ("how does it scale").
  @wh_words ~w(who what when where why how which whose whom
               what's who's where's when's why's how's)
  # Auxiliaries only open a question when a subject follows ("can you ...", not "Will is our CTO").
  @auxiliaries ~w(is are am was were do does did can could will would shall should may might
                  have has had isn't aren't wasn't weren't don't doesn't didn't can't couldn't
                  won't wouldn't shouldn't haven't hasn't)
  @subjects ~w(i you he she it we they this that these those there anyone anybody someone
               somebody everyone)
  # Leading fillers skipped before the first real word ("So, how does it scale").
  @fillers ~w(so and but um uh ok okay well also then right)

  @doc """
  Heuristic: does `text` look like an audience question? True when it ends with `?`,
  starts with a wh-word, or starts with an auxiliary followed by a subject
  ("can you ...", "is this ..."). Leading fillers like "so" or "and" are skipped.
  Does not run the submission filter (`filter_text/1`).
  """
  def question?(text) when is_binary(text) do
    text = String.trim(text)
    text != "" and (String.ends_with?(text, "?") or interrogative_start?(text))
  end

  def question?(_), do: false

  defp interrogative_start?(text) do
    words =
      text
      |> String.downcase()
      |> String.replace(~r/[\x{2018}\x{2019}]/u, "'")
      |> String.split(~r/[^\p{L}']+/u, trim: true)
      |> Enum.drop_while(&(&1 in @fillers))

    case words do
      [w | _] when w in @wh_words -> true
      [aux, subj | _] when aux in @auxiliaries -> subj in @subjects
      _ -> false
    end
  end

  @doc """
  Creates `source: "verbal"` questions from the speech's question-like transcript segments
  (`Takeaway.Transcripts.list_question_segments/1`). Idempotent: a segment that already has
  a question is skipped. Broadcasts `{:question_created, question}` for each new one and
  returns `{:ok, new_questions}`.
  """
  def create_verbal_questions(speech_id) do
    existing =
      from(q in Question,
        where: q.speech_id == ^speech_id and not is_nil(q.transcript_segment_id),
        select: q.transcript_segment_id
      )
      |> Repo.all()
      |> MapSet.new()

    created =
      for seg <- Takeaway.Transcripts.list_question_segments(speech_id),
          seg.id not in existing,
          {:ok, q} <-
            [
              create_question(%{
                "text" => String.trim(seg.text),
                "offset_ms" => seg.start_ms,
                "source" => "verbal",
                "speech_id" => speech_id,
                "transcript_segment_id" => seg.id
              })
            ] do
        tagged =
          Takeaway.Questions.Tagging.attach_current(q, Takeaway.Speeches.get_speech!(speech_id))

        broadcast(speech_id, {:question_created, tagged})
        tagged
      end

    {:ok, created}
  end

  @doc """
  Marks open verbal questions as answered once the speaker responds: a later transcript
  segment that is not itself a question (`question?/1`), starts at or after the question's
  segment ends, and is not by the same labelled speaker as the question. Already answered
  or retracted questions are untouched. Broadcasts `{:question_answered, question}` for each
  and returns `{:ok, answered_questions}`.
  """
  def mark_answered_by_segments(speech_id, now \\ now()) do
    segments = Takeaway.Transcripts.list_segments(speech_id)

    open =
      from(q in Question,
        where:
          q.speech_id == ^speech_id and q.source == "verbal" and is_nil(q.answered_at) and
            is_nil(q.retracted_at) and not is_nil(q.transcript_segment_id)
      )
      |> Repo.all()

    answered =
      for q <- open,
          seg = Enum.find(segments, &(&1.id == q.transcript_segment_id)),
          seg != nil,
          response?(seg, segments),
          {:ok, q} <- [q |> Ecto.Changeset.change(answered_at: now) |> Repo.update()] do
        broadcast(speech_id, {:question_answered, q})
        q
      end

    {:ok, answered}
  end

  defp response?(question_seg, segments) do
    Enum.any?(segments, fn s ->
      s.id != question_seg.id and s.start_ms >= question_seg.end_ms and
        not question?(s.text) and
        not (not is_nil(s.speaker) and s.speaker == question_seg.speaker)
    end)
  end

  defp offset_ms(%Speech{started_at: nil}, _now), do: 0

  defp offset_ms(%Speech{started_at: started}, now),
    do: max(DateTime.diff(now, started, :millisecond), 0)

  defp broadcast(speech_id, msg) do
    Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech_id), msg)
    Phoenix.PubSub.broadcast(Takeaway.PubSub, global_topic(), msg)
  end

  def get_question(id), do: Repo.get(Question, id)
  def get_question!(id), do: Repo.get!(Question, id)

  def create_question(attrs), do: %Question{} |> Question.changeset(attrs) |> Repo.insert()

  def retract_question(%Question{} = question, now \\ now()) do
    question |> Ecto.Changeset.change(retracted_at: now) |> Repo.update()
  end

  def assign_group(%Question{} = question, group_id) do
    question |> Ecto.Changeset.change(group_id: group_id) |> Repo.update()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
