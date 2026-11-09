defmodule Takeaway.Elasticsearch.IndexerTest do
  use ExUnit.Case, async: false

  alias Takeaway.Elasticsearch.Indexer

  setup do
    old = Application.fetch_env!(:takeaway, :elasticsearch)

    Application.put_env(
      :takeaway,
      :elasticsearch,
      Keyword.put(old, :request_options, plug: {Req.Test, __MODULE__})
    )

    on_exit(fn -> Application.put_env(:takeaway, :elasticsearch, old) end)
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:indexed_document, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{result: "created"})
    end)

    :ok
  end

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

      assert_receive {:indexed_document, "/transcript_segments/_doc/seg_1",
                      %{"speech_id" => "speech_100", "text" => "Welcome to KubeCon, everyone."}}
    end

    test "handles missing or nil values gracefully" do
      segment = %{
        id: nil,
        text: nil
      }

      assert :ok = Indexer.index_segment(segment)
      refute_receive {:indexed_document, _, _}
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

      assert_receive {:indexed_document, "/transcript_segments/_doc/1",
                      %{"speech_id" => "speech_99"}}
    end
  end
end
