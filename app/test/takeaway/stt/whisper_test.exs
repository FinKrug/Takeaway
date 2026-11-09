defmodule Takeaway.STT.WhisperTest do
  use ExUnit.Case, async: true
  alias Takeaway.STT.Whisper

  test "parse passes speaker labels through" do
    json =
      Jason.encode!(%{
        "segments" => [
          %{"text" => " hi ", "start" => 0.0, "end" => 1.5, "speaker" => "A"},
          %{"text" => "yo", "start" => 1.5, "end" => 2.0}
        ]
      })

    assert {:ok,
            [
              %{text: "hi", start_ms: 0, end_ms: 1500, speaker: "A"},
              %{text: "yo", start_ms: 1500, end_ms: 2000} = second
            ]} = Whisper.parse(json)

    refute Map.has_key?(second, :speaker)
  end

  test "multipart requests diarization by default and can disable it" do
    assert Whisper.multipart("b", "x", "audio/webm", "m") =~ ~s(name="diarize"\r\n\r\ntrue)
    refute Whisper.multipart("b", "x", "audio/webm", "m", false) =~ "diarize"
  end
end
