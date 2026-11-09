defmodule TakeawayWeb.SpeakerLiveTest do
  use TakeawayWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Events, Speeches, Transcripts}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "My Talk", event_id: event.id, speaker_id: speaker.id})

    Application.put_env(:takeaway, :stt, Takeaway.FakeSTT)
    on_exit(fn -> Application.delete_env(:takeaway, :stt) end)
    %{speech: speech}
  end

  test "renders existing segments and shows new ones live", %{conn: conn, speech: speech} do
    {:ok, _} =
      Transcripts.record_segments(speech.id, [%{text: "earlier", start_ms: 0, end_ms: 900}])

    {:ok, view, html} = live(conn, ~p"/speeches/#{speech.id}/speak")
    assert html =~ "My Talk"
    assert html =~ "earlier"

    {:ok, _} =
      Transcripts.record_segments(speech.id, [
        %{text: "just now", start_ms: 65_000, end_ms: 66_000}
      ])

    html = render(view)
    assert html =~ "just now"
    assert html =~ "01:05"
  end

  test "audio_chunk event transcribes and displays", %{conn: conn, speech: speech} do
    {:ok, view, _} = live(conn, ~p"/speeches/#{speech.id}/speak")
    render_hook(view, "audio_chunk", %{"data" => Base.encode64("pcm"), "offset_ms" => 1000})
    assert render(view) =~ "hello"
    assert [%{start_ms: 1000}, %{start_ms: 1800}] = Transcripts.list_segments(speech.id)
  end

  test "unknown speech redirects", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/speeches/0/speak")
  end
end
