defmodule Takeaway.Elasticsearch.IndexerTest do
  use ExUnit.Case, async: true

  alias Takeaway.Elasticsearch.Indexer

  describe "index_segment/1" do
    test "handles maps with atom or string keys without raising" do
      segment = %{
        id: "seg_1",
        speech_id: "speech_100",
        text: "Welcome to KubeCon, everyone.",
        start_ms: 1000,
        end_ms: 4000,
        slide_number: 1
      }

      assert :ok = Indexer.index_segment(segment)
    end

    test "handles missing or nil values gracefully" do
      segment = %{
        id: nil,
        text: nil
      }

      assert :ok = Indexer.index_segment(segment)
    end

    test "resolves speech_id directly from artifact association without database lookup" do
      artifact = %Takeaway.Speeches.Artifact{id: 99, speech_id: "speech_99"}

      segment = %Takeaway.Speeches.TranscriptSegment{
        id: 1,
        artifact_id: 99,
        artifact: artifact,
        text: "Direct speech ID resolution test",
        start_ms: 0,
        end_ms: 1000
      }

      assert :ok = Indexer.index_segment(segment)
    end
  end
end
