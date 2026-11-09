defmodule TakeawayWeb.SpeakerLiveTest do
  use TakeawayWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Events, Speeches, Transcripts}

  setup %{conn: conn} do
    organizer = organizer_fixture()
    {:ok, event} = Events.create_event(%{name: "Conf"}, organizer)
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "My Talk", event_id: event.id, speaker_id: speaker.id})

    Application.put_env(:takeaway, :stt, Takeaway.FakeSTT)
    on_exit(fn -> Application.delete_env(:takeaway, :stt) end)
    %{speech: speech, conn: log_in_organizer(conn, organizer)}
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

  test "badges a speaker only when the speaker changes, on load and live",
       %{conn: conn, speech: speech} do
    {:ok, _} =
      Transcripts.record_segments(speech.id, [
        %{text: "welcome all", start_ms: 0, end_ms: 900, speaker: "S1"},
        %{text: "still me", start_ms: 900, end_ms: 1800, speaker: "S1"},
        %{text: "unlabelled", start_ms: 1800, end_ms: 2000}
      ])

    {:ok, view, _html} = live(conn, ~p"/speeches/#{speech.id}/speak")
    assert html_badges(view) == ["Speaker 1"]

    {:ok, _} =
      Transcripts.record_segments(speech.id, [
        %{text: "a question", start_ms: 5000, end_ms: 6000, speaker: "S2"},
        %{text: "an answer", start_ms: 6000, end_ms: 7000, speaker: "S1"},
        %{text: "more answer", start_ms: 7000, end_ms: 8000, speaker: "S1"}
      ])

    assert html_badges(view) == ["Speaker 1", "Speaker 2", "Speaker 1"]
  end

  defp html_badges(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#transcript li .rounded-full")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  test "speaker_name and mark_turns" do
    import TakeawayWeb.SpeakerLive, only: [speaker_name: 1, mark_turns: 2]
    assert speaker_name("S3") == "Speaker 3"
    assert speaker_name("SPEAKER_00") == "Speaker 1"
    assert speaker_name("spk_a") == "spk_a"
    assert speaker_name("S0") == "S0"

    segs = [%{speaker: "S1"}, %{speaker: nil}, %{speaker: "S1"}, %{speaker: "S2"}]
    assert {marked, "S2"} = mark_turns(segs, "S1")
    assert Enum.map(marked, & &1.new_speaker) == [false, false, false, true]
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

  describe "access control" do
    test "logged-out visitors go to the login page", %{speech: speech} do
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/speeches/#{speech.id}/speak")
      assert redirected_to(conn) == ~p"/organizers/log_in"
    end

    test "another organizer can't open the page", %{speech: speech} do
      conn = log_in_organizer(Phoenix.ConnTest.build_conn(), organizer_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/speeches/#{speech.id}/speak")
    end
  end
end
