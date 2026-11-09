defmodule Takeaway.Transcripts do
  @moduledoc """
  Live transcript for a speech: turns audio chunks into persisted, timestamped
  segments on the speech's `transcript` artifact, broadcasts them and hands
  them to the indexer.
  """
  alias Takeaway.{Indexer, STT, Speeches}

  def topic(speech_id), do: "speech:#{speech_id}:transcript"
  def subscribe(speech_id), do: Phoenix.PubSub.subscribe(Takeaway.PubSub, topic(speech_id))

  @doc "The speech's Live Transcript artifact, created on first use."
  def get_or_create_artifact(speech_id) do
    case Speeches.list_artifacts(speech_id, "transcript") do
      [artifact | _] ->
        {:ok, artifact}

      [] ->
        Speeches.create_artifact(%{
          kind: "transcript",
          title: "Live Transcript",
          speech_id: speech_id
        })
    end
  end

  def list_segments(speech_id) do
    case Speeches.list_artifacts(speech_id, "transcript") do
      [artifact | _] -> Speeches.list_transcript_segments(artifact.id)
      [] -> []
    end
  end

  @doc "Transcript segments of a speech that look like audience questions (`Questions.question?/1`)."
  def list_question_segments(speech_id) do
    speech_id |> list_segments() |> Enum.filter(&Takeaway.Questions.question?(&1.text))
  end

  @doc """
  Transcribe one audio chunk that began `offset_ms` after the speech's start.
  Returns `{:ok, persisted_segments}`.
  """
  def ingest_chunk(speech_id, audio, content_type, offset_ms)
      when is_binary(audio) and is_integer(offset_ms) and offset_ms >= 0 do
    with {:ok, segments} <- STT.transcribe(audio, content_type) do
      record_segments(speech_id, segments, offset_ms)
    end
  end

  @doc """
  Persist segments (offsets relative to a chunk), broadcast and index them.
  When a new segment looks like a question, it also becomes a `source: "verbal"`
  question (`Takeaway.Questions.create_verbal_questions/1`), and open verbal questions
  followed by a non-question response are marked answered
  (`Takeaway.Questions.mark_answered_by_segments/1`).
  """
  def record_segments(speech_id, segments, offset_ms \\ 0) do
    with {:ok, artifact} <- get_or_create_artifact(speech_id) do
      saved =
        for seg <- segments, {:ok, row} <- [persist(artifact, seg, offset_ms)] do
          Indexer.index_segment(row)
          Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech_id), {:transcript_segment, row})
          row
        end

      if Enum.any?(saved, &Takeaway.Questions.question?(&1.text)),
        do: Takeaway.Questions.create_verbal_questions(speech_id)

      if saved != [], do: Takeaway.Questions.mark_answered_by_segments(speech_id)

      {:ok, saved}
    end
  end

  defp persist(artifact, seg, offset_ms) do
    Speeches.add_transcript_segment(%{
      artifact_id: artifact.id,
      text: seg.text,
      start_ms: seg.start_ms + offset_ms,
      end_ms: seg.end_ms + offset_ms,
      speaker: Map.get(seg, :speaker)
    })
  end
end
