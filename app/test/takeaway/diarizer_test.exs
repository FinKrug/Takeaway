defmodule Takeaway.DiarizerTest do
  # Mutates application env, so not async.
  use ExUnit.Case, async: false

  alias Takeaway.Diarizer

  describe "label/2" do
    test "gives each segment the speaker overlapping it most" do
      segs = [
        %{text: "a", start_ms: 0, end_ms: 1000},
        %{text: "b", start_ms: 1000, end_ms: 3000},
        %{text: "c", start_ms: 2500, end_ms: 4000}
      ]

      turns = [
        %{start_ms: 0, end_ms: 1200, speaker: "S1"},
        %{start_ms: 1200, end_ms: 2800, speaker: "S2"},
        %{start_ms: 2800, end_ms: 4000, speaker: "S1"}
      ]

      assert ["S1", "S2", "S1"] = Diarizer.label(segs, turns) |> Enum.map(& &1.speaker)
    end

    test "sums a speaker's turns before comparing" do
      seg = %{text: "x", start_ms: 0, end_ms: 1000}

      turns = [
        %{start_ms: 0, end_ms: 300, speaker: "S1"},
        %{start_ms: 300, end_ms: 700, speaker: "S2"},
        %{start_ms: 700, end_ms: 1000, speaker: "S1"}
      ]

      assert [%{speaker: "S1"}] = Diarizer.label([seg], turns)
    end

    test "keeps a provider label and leaves unmatched segments alone" do
      segs = [
        %{text: "p", start_ms: 0, end_ms: 500, speaker: "SPEAKER_03"},
        %{text: "gap", start_ms: 5000, end_ms: 6000}
      ]

      turns = [%{start_ms: 0, end_ms: 1000, speaker: "S1"}]

      assert [%{speaker: "SPEAKER_03"}, gap] = Diarizer.label(segs, turns)
      refute Map.has_key?(gap, :speaker)
      assert Diarizer.label(segs, []) == segs
    end
  end

  describe "HTTP" do
    setup do
      Application.put_env(:takeaway, Diarizer.HTTP,
        url: "http://diarizer.test/v1/diarize",
        req_options: [plug: {Req.Test, Diarizer.HTTP}]
      )

      on_exit(fn -> Application.delete_env(:takeaway, Diarizer.HTTP) end)
    end

    test "posts the chunk and session as multipart, returns turns in ms" do
      Req.Test.stub(Diarizer.HTTP, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [ct] = Plug.Conn.get_req_header(conn, "content-type")
        assert ct =~ "multipart/form-data"
        assert body =~ ~s(name="session"\r\n\r\n42)
        assert body =~ ~s(filename="chunk.webm")
        assert body =~ "AUDIO"

        Req.Test.json(conn, %{
          "duration" => 5.0,
          "segments" => [
            %{"start" => 0.031, "end" => 2.4, "speaker" => "S1"},
            %{"start" => 2.5, "end" => 4.9, "speaker" => ""}
          ]
        })
      end)

      assert {:ok, [%{start_ms: 31, end_ms: 2400, speaker: "S1"}]} =
               Diarizer.HTTP.diarize("AUDIO", "audio/webm;codecs=opus", "42")
    end

    test "non-200 is an error" do
      Req.Test.stub(Diarizer.HTTP, &Plug.Conn.send_resp(&1, 400, "could not decode audio"))
      assert {:error, {:http, 400, _}} = Diarizer.HTTP.diarize("x", "audio/ogg", "1")
    end

    test "parse rejects an unexpected body" do
      assert {:error, :bad_response} = Diarizer.HTTP.parse(%{"nope" => 1})
    end
  end

  test "Disabled returns no turns and is the default" do
    Application.delete_env(:takeaway, :diarizer)
    refute Diarizer.enabled?()
    assert {:ok, []} = Diarizer.diarize("a", "audio/webm", 1)
  end
end
