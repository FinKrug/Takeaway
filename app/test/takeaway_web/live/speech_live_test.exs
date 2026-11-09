defmodule TakeawayWeb.SpeechLiveTest do
  use TakeawayWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Takeaway.{Speeches, SpeechCreator, Tickets}

  # A cookieless test conn gets the attendee cookie-check redirect first; follow it.
  defp live_join(conn, path) do
    case live(conn, path) do
      {:error, {:redirect, %{to: to}}} -> live(conn, to)
      other -> other
    end
  end

  setup %{conn: conn} do
    organizer = organizer_fixture()
    %{organizer: organizer, conn: log_in_organizer(conn, organizer)}
  end

  test "creates a speech with uploads and tags, then starts it", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/speeches/new")

    plan = file_input(lv, "#speech-form", :plan, [%{name: "plan.md", content: "# Plan\nhello"}])
    slides = file_input(lv, "#speech-form", :slides, [%{name: "deck.pdf", content: "%PDF-1.4"}])
    render_upload(plan, "plan.md")
    render_upload(slides, "deck.pdf")

    {:ok, show, _} =
      lv
      |> form("#speech-form",
        speech: %{title: "My Talk", description: "d", tags: "Elixir, liveview, elixir"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    html = render(show)
    assert html =~ "My Talk"
    assert html =~ "Start Speech"
    refute html =~ "leaderboard-panel"
    refute html =~ "transcript-panel"

    [speech] = Takeaway.Repo.all(Takeaway.Speeches.Speech)
    assert speech.tags == ["elixir", "liveview"]

    assert [%{kind: "plan", content: "# Plan\nhello"} = a, %{kind: "slides"}] =
             Speeches.list_artifacts(speech.id)

    assert File.exists?(Path.join(SpeechCreator.uploads_dir(), a.url))
    assert html =~ speech.join_code
    assert html =~ "/join/#{speech.join_code}"

    SpeechCreator.subscribe(speech.id)
    show |> element("#start-speech") |> render_click()
    assert has_element?(show, "#leaderboard-panel")
    assert has_element?(show, "#transcript-panel")
    assert has_element?(show, "#panel-transcript-empty")
    refute has_element?(show, "#start-speech")
    assert_receive {:speech_started, %{started_at: %DateTime{}}}
    assert Speeches.get_speech!(speech.id).started_at
  end

  test "dashboard panels render from started_at and vanish at end", %{conn: conn} = ctx do
    {:ok, speech} =
      SpeechCreator.create_speech(%{"title" => "Live"}, [], organizer: ctx.organizer)

    {:ok, speech} = SpeechCreator.start_speech(speech)

    {:ok, _} =
      Takeaway.Transcripts.record_segments(speech.id, [
        %{text: "earlier words", start_ms: 0, end_ms: 1000}
      ])

    {:ok, lv, _html} = live(conn, ~p"/speeches/#{speech.join_code}")
    assert has_element?(lv, "#leaderboard-panel")
    assert has_element?(lv, "#transcript-panel")
    assert has_element?(lv, "#panel-transcript li", "earlier words")

    {:ok, _} =
      Takeaway.Transcripts.record_segments(speech.id, [
        %{text: "fresh words", start_ms: 1000, end_ms: 2000}
      ])

    assert has_element?(lv, "#panel-transcript li", "fresh words")

    {:ok, _} = SpeechCreator.end_speech(speech)
    refute has_element?(lv, "#leaderboard-panel")
    refute has_element?(lv, "#transcript-panel")
  end

  test "title is required", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/speeches/new")
    html = lv |> form("#speech-form", speech: %{title: " "}) |> render_submit()
    assert html =~ "can&#39;t be blank"
  end

  test "leaderboard shows groups live and removes retracted questions", %{
    conn: conn,
    organizer: organizer
  } do
    {:ok, speech} =
      SpeechCreator.create_speech(%{"title" => "Questions"}, [], organizer: organizer)

    {:ok, speech} = SpeechCreator.start_speech(speech)
    {:ok, user} = Takeaway.Accounts.create_anonymous_attendee()
    {:ok, lv, _} = live(conn, ~p"/speeches/#{speech.join_code}")

    {:ok, a} =
      Takeaway.Questions.submit_question(speech, user, %{
        text: "How does distributed consensus work?"
      })

    assert has_element?(lv, "#question-leaderboard", a.text)

    {:ok, b} =
      Takeaway.Questions.submit_question(speech, user, %{
        text: "Explain distributed consensus work?"
      })

    {:ok, _} = Takeaway.Questions.assign_group(a, 900)
    {:ok, _} = Takeaway.Questions.assign_group(b, 900)

    Phoenix.PubSub.broadcast(
      Takeaway.PubSub,
      Takeaway.Questions.topic(speech.id),
      {:question_groups_updated, speech.id}
    )

    assert has_element?(lv, "#question_groups-group-900", a.text)
    assert has_element?(lv, "#question_groups-group-900", "2")
    refute has_element?(lv, "#question_groups-question-#{a.id}")
    {:ok, _} = Takeaway.Questions.retract_question_by(a.id, user)
    assert has_element?(lv, "#question_groups-group-900", b.text)
    assert has_element?(lv, "#question_groups-group-900", "1")
    {:ok, _} = Takeaway.Questions.retract_question_by(b.id, user)
    refute has_element?(lv, "#question_groups-group-900")
  end

  test "join page reflects start over PubSub", %{conn: conn} do
    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "T"})
    {:ok, lv, html} = live_join(conn, ~p"/join/#{speech.join_code}")
    assert html =~ "Waiting"
    {:ok, _} = SpeechCreator.start_speech(speech)
    assert render(lv) =~ "The speech is live"
  end

  test "unknown join code", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/join/NOPE00")
    assert html =~ "No speech found"
  end

  describe "ticket gate on join" do
    setup do
      {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Gated"})
      event = Takeaway.Events.get_event!(speech.event_id)
      {:ok, ticket} = Tickets.create_ticket(event)
      %{speech: speech, ticket: ticket}
    end

    test "events without tickets still open freely", %{conn: conn} do
      {:ok, other} = Takeaway.Events.create_event(%{name: "Free"})
      {:ok, speech} = Speeches.create_speech(%{title: "Open", event_id: other.id})
      {:ok, _lv, html} = live_join(conn, ~p"/join/#{speech.join_code}")
      assert html =~ "Waiting"
    end

    test "missing ticket is gated", %{conn: conn, speech: speech} do
      {:ok, _lv, html} = live(conn, ~p"/join/#{speech.join_code}")
      assert html =~ "join-ticket-required"
      refute html =~ "Waiting"
      refute html =~ "Gated"
    end

    test "invalid ticket is gated", %{conn: conn, speech: speech} do
      {:ok, _lv, html} = live(conn, ~p"/join/#{speech.join_code}?ticket=BOGUS000")
      assert html =~ "join-ticket-invalid"
      refute html =~ "Waiting"
    end

    test "valid ticket (any case) opens the page", %{conn: conn, speech: speech, ticket: t} do
      {:ok, _lv, html} =
        live_join(conn, ~p"/join/#{speech.join_code}?ticket=#{String.downcase(t.code)}")

      assert html =~ "Waiting"
      refute html =~ "join-ticket"
    end
  end

  test "artifact download", %{conn: conn} do
    {:ok, speech} =
      SpeechCreator.create_speech(%{"title" => "T"}, [{"plan", "p.txt", __ENV__.file}])

    [a] = Speeches.list_artifacts(speech.id)
    assert get(conn, ~p"/artifacts/#{a.id}").status == 200
    assert get(conn, ~p"/artifacts/0").status == 404
  end

  describe "organizer access" do
    test "creating a speech needs a login" do
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/speeches/new")
      assert redirected_to(conn) == ~p"/organizers/log_in"
    end

    test "the speech page shows organizer links, and only to the owner", %{
      conn: conn,
      organizer: organizer
    } do
      {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Mine"}, [], organizer: organizer)

      {:ok, _lv, html} = live(conn, ~p"/speeches/#{speech.join_code}")
      assert html =~ ~s(href="/events/#{speech.event_id}/tickets")
      assert html =~ ~s(href="/speeches/#{speech.id}/speak")

      other = log_in_organizer(Phoenix.ConnTest.build_conn(), organizer_fixture())

      assert {:error, {:live_redirect, %{to: "/speeches/new"}}} =
               live(other, ~p"/speeches/#{speech.join_code}")

      anon = Phoenix.ConnTest.build_conn()
      assert redirected_to(get(anon, ~p"/speeches/#{speech.join_code}")) == ~p"/organizers/log_in"
    end

    test "the join page stays public", %{organizer: organizer} do
      {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Mine"}, [], organizer: organizer)
      {:ok, _lv, html} = live_join(Phoenix.ConnTest.build_conn(), ~p"/join/#{speech.join_code}")
      assert html =~ "Waiting"
    end
  end
end
