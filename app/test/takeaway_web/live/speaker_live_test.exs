defmodule TakeawayWeb.SpeakerLiveTest do
  use TakeawayWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Events, Questions, Speeches, Transcripts}

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

  describe "question list" do
    setup do
      {:ok, attendee} = Accounts.create_anonymous_attendee()
      %{attendee: attendee}
    end

    test "renders existing questions with offset, slide and source",
         %{conn: conn, speech: speech, attendee: attendee} do
      {:ok, typed} =
        Questions.create_question(%{
          text: "How does it scale?",
          offset_ms: 65_000,
          slide_number: 4,
          speech_id: speech.id,
          user_id: attendee.id
        })

      {:ok, verbal} =
        Questions.create_question(%{
          text: "What about latency?",
          offset_ms: 2_000,
          source: "verbal",
          speech_id: speech.id
        })

      {:ok, retracted} = Questions.submit_question(speech, attendee, %{text: "Never mind"})
      {:ok, _} = Questions.retract_question(retracted)

      {:ok, view, _} = live(conn, ~p"/speeches/#{speech.id}/speak")

      typed_li = "#questions-#{typed.id}"
      verbal_li = "#questions-#{verbal.id}"
      assert has_element?(view, typed_li, "How does it scale?")
      assert has_element?(view, typed_li, "01:05")
      assert has_element?(view, typed_li, "Slide 4")
      assert has_element?(view, typed_li, "Typed")
      assert has_element?(view, verbal_li, "What about latency?")
      assert has_element?(view, verbal_li, "00:02")
      assert has_element?(view, verbal_li, "Spoken")
      refute has_element?(view, verbal_li, "Slide")
      refute has_element?(view, "#questions-#{retracted.id}")
      # the empty-state row is still in the DOM; CSS (`only:`) hides it next to items
      assert has_element?(view, "#questions > li:not(#questions-empty)")
      # loaded questions don't animate in
      refute has_element?(view, "#questions .motion-safe\\:animate-enter")
    end

    test "shows new questions live and removes retracted ones",
         %{conn: conn, speech: speech, attendee: attendee} do
      {:ok, view, _} = live(conn, ~p"/speeches/#{speech.id}/speak")
      assert has_element?(view, "#questions-empty", "No questions yet")
      refute has_element?(view, "#questions > li:not(#questions-empty)")

      {:ok, q} = Questions.submit_question(speech, attendee, %{text: "Live one?"})
      assert has_element?(view, "#questions-#{q.id}", "Live one?")
      assert has_element?(view, "#questions-#{q.id}.motion-safe\\:animate-enter")

      # a repeated event updates rather than duplicates
      send(view.pid, {:question_created, %{q | text: "Live one, edited?"}})
      assert has_element?(view, "#questions-#{q.id}", "Live one, edited?")
      assert render(view) |> String.split(~s(id="questions-#{q.id}")) |> length() == 2

      {:ok, _} = Questions.retract_question_by(q.id, attendee)
      refute has_element?(view, "#questions-#{q.id}")
      refute has_element?(view, "#questions > li:not(#questions-empty)")
      assert has_element?(view, "#questions-empty", "No questions yet")
    end

    test "verbal questions appear live and unrelated messages are ignored",
         %{conn: conn, speech: speech} do
      {:ok, view, _} = live(conn, ~p"/speeches/#{speech.id}/speak")

      {:ok, q} =
        Questions.create_question(%{
          text: "Can you repeat that?",
          offset_ms: 3_000,
          source: "verbal",
          speech_id: speech.id
        })

      Phoenix.PubSub.broadcast(
        Takeaway.PubSub,
        Questions.topic(speech.id),
        {:question_created, q}
      )

      send(view.pid, {:question_answered, q})
      send(view.pid, {:speech_started, speech})
      send(view.pid, {:question_retracted, %{q | id: -1}})

      # the view survived the unrelated messages and the unknown retract
      assert has_element?(view, "#questions-#{q.id}", "Spoken")
    end
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
