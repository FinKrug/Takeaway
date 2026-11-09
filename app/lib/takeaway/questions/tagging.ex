defmodule Takeaway.Questions.Tagging do
  @moduledoc "Best-effort question context. Submission offsets stay unchanged; matched context has its own offset."
  import Ecto.Query
  require Logger
  alias Takeaway.{Elasticsearch, Questions, Repo, Slides, Speeches, SpeechCreator}
  alias Takeaway.Questions.{Grouping, Question}
  alias Takeaway.Speeches.{Artifact, TranscriptSegment}
  alias Takeaway.Slides.Slide

  @search_options [
    connect_options: [timeout: 200],
    receive_timeout: 200,
    request_timeout: 250,
    retry: false
  ]

  @doc "Capture local context only. Failure never undoes an already saved question."
  def attach_current(question, speech, opts \\ []) do
    segment =
      if question.source == "verbal",
        do: Repo.get(TranscriptSegment, question.transcript_segment_id),
        else: active_segment(question.speech_id, question.offset_ms)

    current = Speeches.get_speech(speech.id) || speech

    source =
      case Keyword.get(opts, :slide_source) do
        source when source in ["current", "manual"] -> source
        _ -> if(question.slide_number, do: "manual", else: "current")
      end

    slide =
      if source == "manual",
        do: question.slide_number,
        else: SpeechCreator.current_slide(current, Slides.count_slides(current.id))

    save(question, segment, slide, slide_source: source)
  rescue
    error ->
      Logger.warning("Question context unavailable: #{Exception.message(error)}")
      question
  end

  @doc "Enrich with verified same-speech ES candidates, outside the submission path."
  def enrich(id) do
    case Questions.get_question(id) do
      %Question{retracted_at: nil} = question ->
        matched = if question.source == "typed", do: matched_segment(question)
        segment = matched || active_segment(question.speech_id, question.offset_ms)

        slide =
          if question.source == "typed" and question.slide_source != "manual",
            do: matched_slide(question)

        save(question, segment, slide,
          context_source: if(matched, do: "matched", else: "current"),
          slide_source: if(slide, do: "matched")
        )

      _ ->
        nil
    end
  end

  @doc "Attach a delayed transcript only to untagged questions whose timestamp it covers."
  def attach_delayed(speech_id, segment) do
    Repo.all(
      from q in Question,
        where:
          q.speech_id == ^speech_id and is_nil(q.retracted_at) and
            is_nil(q.context_segment_id) and q.offset_ms >= ^segment.start_ms and
            q.offset_ms < ^segment.end_ms,
        order_by: q.id
    )
    |> Enum.each(&save(&1, segment, &1.slide_number))
  end

  defp active_segment(speech_id, offset) do
    Repo.one(
      from t in TranscriptSegment,
        join: a in Artifact,
        on: a.id == t.artifact_id,
        where:
          a.speech_id == ^speech_id and a.kind == "transcript" and
            t.start_ms <= ^offset and t.end_ms > ^offset,
        order_by: [desc: t.start_ms, desc: t.id],
        limit: 1
    )
  end

  defp matched_segment(question) do
    hits("transcript_segments", question, %{match: %{text: question.text}})
    |> Enum.find_value(fn hit ->
      with {id, ""} <-
             Integer.parse(to_string(get_in(hit, ["_source", "segment_id"]) || hit["_id"])),
           %TranscriptSegment{} = segment <-
             Repo.one(
               from t in TranscriptSegment,
                 join: a in Artifact,
                 on: a.id == t.artifact_id,
                 where:
                   t.id == ^id and a.speech_id == ^question.speech_id and a.kind == "transcript" and
                     t.start_ms <= ^question.offset_ms
             ),
           true <- Grouping.similarity(question.text, segment.text) >= 0.15 do
        segment
      else
        _ -> nil
      end
    end)
  end

  defp matched_slide(question) do
    hits("slides", question, %{multi_match: %{query: question.text, fields: ["title", "content"]}})
    |> Enum.find_value(fn hit ->
      with n when is_integer(n) and n > 0 <- get_in(hit, ["_source", "slide_number"]),
           %Slide{} = slide <- Repo.get_by(Slide, speech_id: question.speech_id, slide_number: n),
           true <- Grouping.similarity(question.text, slide.text) >= 0.15 do
        n
      else
        _ -> nil
      end
    end)
  end

  defp hits(index, question, match) do
    query = %{
      size: 5,
      query: %{
        bool: %{must: [match], filter: [%{term: %{speech_id: to_string(question.speech_id)}}]}
      }
    }

    case Elasticsearch.search(index, query, @search_options) do
      {:ok, %{"hits" => hits}} when is_list(hits) -> Enum.take(hits, 5)
      _ -> []
    end
  end

  defp save(question, segment, slide, opts \\ []) do
    # Re-read under the row lock to avoid racing a retraction or another replica.
    result =
      Repo.transaction(fn ->
        current = Repo.one!(from q in Question, where: q.id == ^question.id, lock: "FOR UPDATE")

        if current.retracted_at do
          current
        else
          context_source = Keyword.get(opts, :context_source, "current")
          # A delayed chunk or a duplicate delivery cannot erase a semantic match.
          segment =
            if current.context_source == "matched" and context_source != "matched",
              do: nil,
              else: segment

          segment_id = if segment, do: segment.id, else: current.context_segment_id
          offset = if segment, do: segment.start_ms, else: current.context_offset_ms
          slide_source = Keyword.get(opts, :slide_source)

          replace_slide? =
            (is_nil(current.slide_source) and slide_source in ["current", "manual"]) or
              (slide && current.slide_source != "manual" &&
                 (current.slide_number == nil || slide_source == "matched"))

          slide = if replace_slide?, do: slide, else: current.slide_number

          attrs = %{
            context_segment_id: segment_id,
            context_offset_ms: offset,
            context_source: if(segment, do: context_source, else: current.context_source),
            slide_number: slide,
            slide_source:
              cond do
                current.slide_source == "manual" or slide_source == "manual" -> "manual"
                replace_slide? -> slide_source
                true -> current.slide_source
              end,
            tag: label(slide, offset || current.offset_ms)
          }

          current |> Ecto.Changeset.change(attrs) |> Repo.update!()
        end
      end)

    case result do
      {:ok, updated} ->
        if is_nil(updated.retracted_at) and updated != question do
          for topic <- [Questions.topic(updated.speech_id), Questions.global_topic()] do
            Phoenix.PubSub.broadcast(Takeaway.PubSub, topic, {:question_tagged, updated})
          end
        end

        updated

      {:error, _} ->
        question
    end
  end

  @doc "A compact, mobile-readable slide and speech-time label."
  def label(slide, offset) do
    seconds = div(max(offset, 0), 1_000)

    time =
      "#{String.pad_leading(to_string(div(seconds, 60)), 2, "0")}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"

    if slide, do: "Slide #{slide} · #{time}", else: time
  end
end
