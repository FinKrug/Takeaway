defmodule Takeaway.Elasticsearch.Indexer do
  @moduledoc """
  Implements `Takeaway.Indexer` to stream transcript segments into Elasticsearch.

  Slides (`index_slide/1`) are indexed synchronously: `Takeaway.Slides` already
  calls it from a background task and counts failures.
  """
  @behaviour Takeaway.Indexer

  alias Takeaway.Elasticsearch
  alias Takeaway.Repo
  alias Takeaway.Speeches.Artifact
  require Logger

  @impl true
  def index_segment(segment) do
    Task.start(fn -> do_index_segment(segment) end)
    :ok
  end

  defp do_index_segment(segment) do
    speech_id = resolve_speech_id(segment)

    doc = %{
      segment_id: segment_id(segment),
      speech_id: speech_id,
      text: segment_text(segment),
      start_ms: segment_field(segment, :start_ms) || 0,
      end_ms: segment_field(segment, :end_ms) || 0,
      slide_number: segment_field(segment, :slide_number)
    }

    case Elasticsearch.index_transcript_segment(doc) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Elasticsearch.Indexer] Failed to index transcript segment: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    e ->
      Logger.warning("[Elasticsearch.Indexer] Exception indexing segment: #{inspect(e)}")
      :ok
  end

  @impl true
  def index_slide(slide) do
    case Elasticsearch.index_slide(slide) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp resolve_speech_id(segment) do
    cond do
      speech_id = segment_field(segment, :speech_id) ->
        speech_id

      artifact = segment_field(segment, :artifact) ->
        case artifact do
          %Artifact{speech_id: sid} -> sid
          _ -> lookup_speech_id_by_artifact(segment_field(segment, :artifact_id))
        end

      artifact_id = segment_field(segment, :artifact_id) ->
        lookup_speech_id_by_artifact(artifact_id)

      true ->
        nil
    end
  end

  defp lookup_speech_id_by_artifact(nil), do: nil

  defp lookup_speech_id_by_artifact(artifact_id) do
    case Repo.get(Artifact, artifact_id) do
      %Artifact{speech_id: sid} -> sid
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp segment_id(%{id: id}), do: id
  defp segment_id(%{"id" => id}), do: id
  defp segment_id(%{segment_id: id}), do: id
  defp segment_id(%{"segment_id" => id}), do: id
  defp segment_id(_), do: nil

  defp segment_text(%{text: text}), do: text
  defp segment_text(%{"text" => text}), do: text
  defp segment_text(_), do: ""

  defp segment_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp segment_field(_, _), do: nil
end
