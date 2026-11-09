defmodule Takeaway.TranscriptsTest do
  # Mutates application env, so not async.
  use Takeaway.DataCase, async: false

  alias Takeaway.{Events, Accounts, Speeches, Transcripts}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, speaker_id: speaker.id})

    Application.put_env(:takeaway, :stt, Takeaway.FakeSTT)
    Application.put_env(:takeaway, :indexer, Takeaway.FakeIndexer)
    Application.put_env(:takeaway, :indexer_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:takeaway, :stt)
      Application.delete_env(:takeaway, :indexer)
      Application.delete_env(:takeaway, :indexer_test_pid)
    end)

    %{speech: speech}
  end

  test "ingest persists offset segments, broadcasts and indexes", %{speech: speech} do
    Transcripts.subscribe(speech.id)
    assert {:ok, [a, b]} = Transcripts.ingest_chunk(speech.id, "audio", "audio/webm", 5000)
    assert {a.start_ms, a.end_ms} == {5000, 5800}
    assert {b.start_ms, b.end_ms} == {5800, 6500}

    assert_receive {:transcript_segment, %{text: "hello"}}
    assert_receive {:transcript_segment, %{text: "world"}}
    assert_receive {:indexed, %{text: "hello"}}
    assert_receive {:indexed, %{text: "world"}}

    assert ["hello", "world"] = Enum.map(Transcripts.list_segments(speech.id), & &1.text)
    assert [%{kind: "transcript"}] = Speeches.list_artifacts(speech.id, "transcript")
  end

  test "reuses a single transcript artifact", %{speech: speech} do
    {:ok, _} = Transcripts.ingest_chunk(speech.id, "a", "audio/webm", 0)
    {:ok, _} = Transcripts.ingest_chunk(speech.id, "b", "audio/webm", 2000)
    assert [_] = Speeches.list_artifacts(speech.id, "transcript")
    assert length(Transcripts.list_segments(speech.id)) == 4
  end

  test "STT errors are returned and nothing is stored", %{speech: speech} do
    assert {:error, :down} = Transcripts.ingest_chunk(speech.id, "boom", "audio/webm", 0)
    assert Transcripts.list_segments(speech.id) == []
  end

  test "Whisper.parse handles verbose_json and plain text" do
    json =
      ~s({"segments":[{"text":" hi ","start":0.5,"end":1.25},{"text":" ","start":2,"end":3}]})

    assert {:ok, [%{text: "hi", start_ms: 500, end_ms: 1250}]} = Takeaway.STT.Whisper.parse(json)
    assert {:ok, [%{text: "yo"}]} = Takeaway.STT.Whisper.parse(~s({"text":"yo"}))
    assert {:error, :bad_response} = Takeaway.STT.Whisper.parse("nope")
  end

  test "Whisper.parse keeps a diarized speaker label and omits blank ones" do
    json =
      ~s({"segments":[{"text":"hi","start":0,"end":1,"speaker":"SPEAKER_00"},{"text":"yo","start":1,"end":2,"speaker":""},{"text":"ok","start":2,"end":3}]})

    assert {:ok, [a, b, c]} = Takeaway.STT.Whisper.parse(json)
    assert a.speaker == "SPEAKER_00"
    refute Map.has_key?(b, :speaker)
    refute Map.has_key?(c, :speaker)
  end

  test "record_segments stores the speaker label, nil when absent", %{speech: speech} do
    segs = [
      %{text: "hi", start_ms: 0, end_ms: 100, speaker: "SPEAKER_01"},
      %{text: "there", start_ms: 100, end_ms: 200}
    ]

    assert {:ok, [a, b]} = Transcripts.record_segments(speech.id, segs)
    assert a.speaker == "SPEAKER_01"
    assert b.speaker == nil

    assert ["SPEAKER_01", nil] = Enum.map(Transcripts.list_segments(speech.id), & &1.speaker)
  end
end
