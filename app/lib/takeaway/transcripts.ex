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

  @doc "Persist segments (offsets relative to a chunk), broadcast and index them."
  def record_segments(speech_id, segments, offset_ms \\ 0) do
    with {:ok, artifact} <- get_or_create_artifact(speech_id) do
      saved =
        for seg <- segments, {:ok, row} <- [persist(artifact, seg, offset_ms)] do
          Indexer.index_segment(row)
          Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech_id), {:transcript_segment, row})
          row
        end

      {:ok, saved}
    end
  end

  defp persist(artifact, seg, offset_ms) do
    Speeches.add_transcript_segment(%{
      artifact_id: artifact.id,
      text: seg.text,
      start_ms: seg.start_ms + offset_ms,
      end_ms: seg.end_ms + offset_ms
    })
  end
end
