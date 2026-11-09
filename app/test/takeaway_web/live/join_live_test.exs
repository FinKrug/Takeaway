defmodule TakeawayWeb.JoinLiveTest do
  # Mutates the :question_filter application env, so not async.
  use TakeawayWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Notes, Questions, Repo, Slides, SpeechCreator}
  alias Takeaway.Notes.Note
  alias Takeaway.Questions.Question

  setup %{conn: conn} do
    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Talk"})
    {:ok, attendee} = Accounts.create_anonymous_attendee()
    conn = init_test_session(conn, %{"user_id" => attendee.id})
    %{conn: conn, speech: speech, attendee: attendee}
  end

  defp started(%{speech: speech}) do
    {:ok, speech} = SpeechCreator.start_speech(speech)
    %{speech: speech}
  end

  defp ask(speech, user, text) do
    {:ok, q} = Questions.submit_question(speech, user, %{"text" => text})
    q
  end

  describe "live captions" do
    test "hidden until the speech starts, then shows transcript live, gone at end",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      refute has_element?(lv, "#live-captions")

      {:ok, started} = SpeechCreator.start_speech(speech)
      send(lv.pid, {:speech_started, started})
      assert has_element?(lv, "#live-captions-log[role=log]")
      assert has_element?(lv, "#captions-empty")

      {:ok, _} =
        Takeaway.Transcripts.record_segments(speech.id, [
          %{text: "hello captions", start_ms: 0, end_ms: 1000}
        ])

      assert has_element?(lv, "#captions li", "hello captions")

      {:ok, _} = SpeechCreator.end_speech(started)
      refute has_element?(lv, "#live-captions")
    end

    test "late joiner sees earlier segments", %{conn: conn, speech: speech} do
      {:ok, speech} = SpeechCreator.start_speech(speech)

      {:ok, _} =
        Takeaway.Transcripts.record_segments(speech.id, [
          %{text: "earlier words", start_ms: 0, end_ms: 1000}
        ])

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#captions li", "earlier words")
    end

    test "waiting-room attendee gets segments recorded before they saw the start",
         %{conn: conn, speech: speech} do
      # Recorded before this LiveView exists, so its broadcast never reaches it,
      # and mount skips captions because the speech hasn't started.
      {:ok, _} =
        Takeaway.Transcripts.record_segments(speech.id, [
          %{text: "missed words", start_ms: 0, end_ms: 1000}
        ])

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      {:ok, started} = SpeechCreator.start_speech(speech)
      send(lv.pid, {:speech_started, started})
      assert has_element?(lv, "#captions li", "missed words")
    end
  end

  test "logo without wordmark has an accessible name" do
    html =
      Phoenix.LiveViewTest.rendered_to_string(
        TakeawayWeb.CoreComponents.logo(%{class: "h-5", wordmark: false})
      )

    assert html =~ ~s(aria-label="takeaway")
  end

  describe "waiting room" do
    test "notes open, questions closed until the speech starts, then live without reload",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      assert has_element?(lv, "#join-waiting")
      assert has_element?(lv, "#questions-not-started")
      refute has_element?(lv, "#question-form")
      assert has_element?(lv, "#note-body")
      refute has_element?(lv, "#note-body[disabled]")

      {:ok, started} = SpeechCreator.start_speech(speech)
      # A duplicate start broadcast is harmless.
      send(lv.pid, {:speech_started, started})

      assert has_element?(lv, "#join-live")
      refute has_element?(lv, "#join-waiting")
      assert has_element?(lv, "#question-form")
      refute has_element?(lv, "#questions-not-started")
    end

    test "joining after the start skips the waiting room", %{conn: conn} = ctx do
      %{speech: speech} = started(ctx)
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#join-live")
      refute has_element?(lv, "#join-waiting")
    end

    test "after the end questions are closed but the list stays", %{conn: conn} = ctx do
      %{speech: speech} = started(ctx)
      ask(speech, ctx.attendee, "Still visible?")
      {:ok, _} = SpeechCreator.end_speech(speech)

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      # Let the attendee summary finish before the test (and its sandbox) ends.
      render_async(lv)
      assert has_element?(lv, "#questions-closed")
      refute has_element?(lv, "#question-form")
      assert render(lv) =~ "Still visible?"
    end

    test "unrelated messages on the topics don't crash the page", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      send(lv.pid, {:something_new, :payload})
      send(lv.pid, :whatever)
      assert has_element?(lv, "#join-waiting")
    end
  end

  describe "notes" do
    test "change autosaves one note that survives a remount",
         %{conn: conn, speech: speech, attendee: a} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      refute has_element?(lv, "#note-saved")

      lv |> form("#note-form", note: %{body: "first"}) |> render_change()
      lv |> form("#note-form", note: %{body: "first and second"}) |> render_change()

      assert has_element?(lv, "#note-saved")
      assert [%Note{body: "first and second"}] = Notes.list_notes(speech.id, a.id)

      {:ok, lv2, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert lv2 |> element("#note-body") |> render() =~ "first and second"
    end

    test "an emptied note saves as empty", %{conn: conn, speech: speech, attendee: a} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      lv |> form("#note-form", note: %{body: "x"}) |> render_change()
      lv |> form("#note-form", note: %{body: ""}) |> render_change()
      assert Notes.get_note_for(speech.id, a.id).body == ""
    end

    test "a too long note shows an error and is not saved",
         %{conn: conn, speech: speech, attendee: a} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      long = String.duplicate("a", Note.max_length() + 1)
      html = lv |> form("#note-form") |> render_change(%{note: %{body: long}})

      assert has_element?(lv, "#note-not-saved")
      assert html =~ "should be at most"
      assert Notes.get_note_for(speech.id, a.id) == nil
    end

    test "cookies off: the cookie check ends in the read-only state", %{speech: speech} do
      path = ~p"/join/#{speech.join_code}"
      assert {:error, {:redirect, %{to: to}}} = live(build_conn(), path)
      assert to == path <> "?cookie_check=1"

      {:ok, lv, _html} = live(build_conn(), to)
      assert has_element?(lv, "#join-waiting")
      assert has_element?(lv, "#notes-unavailable")
      assert has_element?(lv, "#note-body[disabled]")
    end

    test "without an attendee (cookies off, crawlers) the editor is disabled", %{speech: speech} do
      conn =
        build_conn()
        |> put_req_header("user-agent", "Twitterbot/1.0")

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#notes-unavailable")
      assert has_element?(lv, "#note-body[disabled]")
    end
  end

  describe "question form" do
    setup :started

    test "a valid question is saved, broadcast, listed and the form cleared",
         %{conn: conn, speech: speech, attendee: a} do
      Questions.subscribe(speech.id)
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      lv
      |> form("#question-form", question: %{text: "  How does it scale? ", slide_number: "3"})
      |> render_submit()

      assert [%Question{text: "How does it scale?", slide_number: 3, user_id: uid} = q] =
               Questions.list_questions(speech.id)

      assert uid == a.id
      assert q.offset_ms >= 0
      assert_receive {:question_created, %Question{id: id}}
      assert id == q.id

      assert has_element?(lv, "#question-#{q.id}", "How does it scale?")
      refute lv |> element("#question-text") |> render() =~ "How does it scale?"
      assert has_element?(lv, "#my-question-count", "1")
    end

    test "blank text shows an inline error and saves nothing", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      html = lv |> form("#question-form", question: %{text: "   "}) |> render_submit()
      assert html =~ "type a question first"
      assert Questions.list_questions(speech.id) == []
    end

    test "default filter errors appear inline and allow a corrected question",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      for {text, message} <- [
            {"Thanks everyone", "please ask a question about the talk"},
            {"Why this sh1t?", "please rephrase your question without profanity"}
          ] do
        html = lv |> form("#question-form", question: %{text: text}) |> render_submit()
        assert html =~ message
        assert Questions.list_questions(speech.id) == []
      end

      lv |> form("#question-form", question: %{text: "How does it scale"}) |> render_submit()
      assert [%{text: "How does it scale"}] = Questions.list_questions(speech.id)
    end

    test "an invalid slide number shows an error", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      html =
        lv
        |> form("#question-form", question: %{text: "Hi?", slide_number: "0"})
        |> render_submit()

      assert html =~ "must be greater than 0"
      assert Questions.list_questions(speech.id) == []
    end

    test "filtered text shows the filter's reason and saves nothing",
         %{conn: conn, speech: speech} do
      Application.put_env(:takeaway, :question_filter, fn _ ->
        {:error, "please keep it civil"}
      end)

      on_exit(fn -> Application.delete_env(:takeaway, :question_filter) end)

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      html = lv |> form("#question-form", question: %{text: "rude"}) |> render_submit()
      assert html =~ "please keep it civil"
      assert Questions.list_questions(speech.id) == []
    end

    test "a second question within a few seconds is rate limited",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      lv |> form("#question-form", question: %{text: "One?"}) |> render_submit()
      html = lv |> form("#question-form", question: %{text: "Two?"}) |> render_submit()
      assert html =~ "wait a few seconds"
      assert [%{text: "One?"}] = Questions.list_questions(speech.id)
    end
  end

  describe "current slide" do
    setup :started

    test "is shown, follows the speaker and tags submitted questions",
         %{conn: conn, speech: speech} do
      {:ok, _} = Slides.upsert_slides(speech.id, ["one", "two", "three", "four"])
      {:ok, speech} = SpeechCreator.set_current_slide(speech, 2, 4)

      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#join-current-slide", "Slide 2")
      assert has_element?(lv, "#question-slide[value='2']")

      # the attendee starts typing, then the speaker moves on
      lv |> form("#question-form", question: %{text: "Half typed"}) |> render_change()
      {:ok, _} = SpeechCreator.set_current_slide(speech, 3, 4)
      assert has_element?(lv, "#join-current-slide", "Slide 3")
      assert has_element?(lv, "#question-slide[value='3']")
      assert lv |> element("#question-text") |> render() =~ "Half typed"

      lv |> form("#question-form", question: %{text: "About this slide?"}) |> render_submit()
      assert [%Question{slide_number: 3}] = Questions.list_questions(speech.id)
      # the cleared form is prefilled again
      assert has_element?(lv, "#question-slide[value='3']")
    end

    test "a slide the attendee picked is kept when the speaker moves on",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      # no deck and no slide picked yet: nothing shown, field empty
      refute has_element?(lv, "#join-current-slide")
      refute has_element?(lv, "#question-slide[value]")

      {:ok, speech} = SpeechCreator.set_current_slide(speech, 1, 0)
      assert has_element?(lv, "#question-slide[value='1']")

      lv |> form("#question-form", question: %{text: "Q", slide_number: "7"}) |> render_change()
      {:ok, _} = SpeechCreator.set_current_slide(speech, 2, 0)
      assert has_element?(lv, "#join-current-slide", "Slide 2")
      assert has_element?(lv, "#question-slide[value='7']")

      lv |> form("#question-form", question: %{text: "Back there?"}) |> render_submit()
      assert [%Question{slide_number: 7}] = Questions.list_questions(speech.id)
    end

    test "slides extracted after joining cap the shown slide", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      {:ok, _} = Slides.upsert_slides(speech.id, ["one", "two", "three"])

      # a speaker page with an out-of-date count sends a slide past the deck
      {:ok, _} = SpeechCreator.set_current_slide(speech, 5, 0)
      assert has_element?(lv, "#join-current-slide", "Slide 3")
      assert has_element?(lv, "#question-slide[value='3']")
    end

    test "a filtered question shows its error and keeps the slide",
         %{conn: conn, speech: speech} do
      {:ok, speech} = SpeechCreator.set_current_slide(speech, 2, 0)
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      html = lv |> form("#question-form", question: %{text: "Thanks everyone"}) |> render_submit()
      assert html =~ "please ask a question about the talk"
      assert has_element?(lv, "#question-slide[value='2']")
      assert Questions.list_questions(speech.id) == []
    end

    test "another speech's slide changes are ignored", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      send(lv.pid, {:slide_changed, speech.id + 1, 5})
      refute has_element?(lv, "#join-current-slide")
    end

    test "attendees can't change the slide", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      refute has_element?(lv, "#slide-controls")
      refute has_element?(lv, "#slide-next")

      # the speaker page refuses anyone but the owning organizer
      assert {:error, {:redirect, _}} = live(conn, ~p"/speeches/#{speech.id}/speak")
      assert Takeaway.Speeches.get_speech!(speech.id).current_slide == nil
    end
  end

  test "submitting before the start is refused", %{conn: conn, speech: speech} do
    {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
    render_submit(lv, "submit_question", %{"question" => %{"text" => "Early?"}})
    assert Questions.list_questions(speech.id) == []
  end

  describe "question stream" do
    setup :started

    test "renders existing questions in order, without retracted ones",
         %{conn: conn, speech: speech, attendee: a} do
      q1 = ask(speech, a, "First question?")
      q2 = ask(speech, a, "Second question?")
      gone = ask(speech, a, "Retracted question?")
      {:ok, _} = Questions.retract_question(gone)

      {:ok, lv, html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#questions[phx-update=stream]")
      assert has_element?(lv, "#question-#{q1.id}", "First question?")
      assert has_element?(lv, "#question-#{q2.id}", "Second question?")
      refute html =~ "Retracted question?"
      {first, _} = :binary.match(html, "First question?")
      {second, _} = :binary.match(html, "Second question?")
      assert first < second
      refute has_element?(lv, "#questions-empty")
      # The initial load does not animate.
      refute lv |> element("#question-#{q1.id}") |> render() =~ "animate-enter"
    end

    test "inserts and removes questions from others live, with the empty state",
         %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#questions-empty", "No questions yet")

      {:ok, other} = Accounts.create_anonymous_attendee()
      q = ask(speech, other, "From someone else?")
      assert has_element?(lv, "#question-#{q.id}", "From someone else?")
      assert lv |> element("#question-#{q.id}") |> render() =~ "animate-enter"
      refute has_element?(lv, "#questions-empty")
      refute has_element?(lv, "#retract-question-#{q.id}")

      # A duplicate broadcast updates in place instead of duplicating.
      send(lv.pid, {:question_created, q})
      assert render(lv) |> String.split("From someone else?") |> length() == 2

      {:ok, _} = Questions.retract_question_by(q.id, other)
      refute has_element?(lv, "#question-#{q.id}")
      assert has_element?(lv, "#questions-empty")

      # Retracting something that isn't listed is a no-op.
      send(lv.pid, {:question_retracted, %{q | id: -1}})
      assert has_element?(lv, "#questions-empty")
    end

    test "tag enrichment updates the question chip without duplicating or resurrecting it",
         %{conn: conn, speech: speech, attendee: a} do
      q = ask(speech, a, "How does consensus work?")
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      tagged = %{q | tag: "Slide 4 · 12:34"}
      send(lv.pid, {:question_tagged, tagged})
      assert has_element?(lv, "#question-#{q.id}", "Slide 4 · 12:34")
      assert has_element?(lv, "#my-question-count", "1")
      lv |> element("#retract-question-#{q.id}") |> render_click()
      send(lv.pid, {:question_tagged, tagged})
      refute has_element?(lv, "#question-#{q.id}")
    end

    test "verbal questions appear and can't be retracted", %{conn: conn, speech: speech} do
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      {:ok, q} =
        Questions.create_question(%{
          text: "Asked from the floor?",
          source: "verbal",
          speech_id: speech.id
        })

      send(lv.pid, {:question_created, q})
      assert has_element?(lv, "#question-#{q.id}", "Asked aloud")
      refute has_element?(lv, "#retract-question-#{q.id}")
    end
  end

  describe "retract" do
    setup :started

    test "own questions can be retracted, which removes them everywhere",
         %{conn: conn, speech: speech, attendee: a} do
      q = ask(speech, a, "Mine?")
      Questions.subscribe(speech.id)
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
      assert has_element?(lv, "#my-question-count", "1")

      lv |> element("#retract-question-#{q.id}") |> render_click()

      refute has_element?(lv, "#question-#{q.id}")
      refute has_element?(lv, "#my-question-count")
      assert Repo.get!(Question, q.id).retracted_at
      assert_receive {:question_retracted, %Question{id: id}}
      assert id == q.id
    end

    test "a forged retract of someone else's question changes nothing",
         %{conn: conn, speech: speech} do
      {:ok, other} = Accounts.create_anonymous_attendee()
      q = ask(speech, other, "Not yours?")
      {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")

      refute has_element?(lv, "#retract-question-#{q.id}")
      html = render_click(lv, "retract", %{"id" => to_string(q.id)})
      assert html =~ "only retract your own"
      assert has_element?(lv, "#question-#{q.id}")
      refute Repo.get!(Question, q.id).retracted_at

      # Garbage ids don't crash either.
      assert render_click(lv, "retract", %{"id" => "nope"}) =~ "Could not retract"
    end
  end

  test "notes and questions are tab panels with accessible tabs", %{conn: conn, speech: speech} do
    {:ok, lv, _html} = live(conn, ~p"/join/#{speech.join_code}")
    assert has_element?(lv, "[role=tablist]")
    assert has_element?(lv, "#tab-notes[role=tab][aria-selected=true][aria-controls=panel-notes]")
    assert has_element?(lv, "#tab-questions[role=tab][aria-selected=false]")
    assert has_element?(lv, "#tab-notes[tabindex='0']")
    assert has_element?(lv, "#tab-questions[tabindex='-1']")
    assert has_element?(lv, "#attendee-tablist[phx-hook=TabList]")
    assert has_element?(lv, "#panel-notes[role=tabpanel]")
    assert has_element?(lv, "#panel-questions[role=tabpanel]")
  end
end
