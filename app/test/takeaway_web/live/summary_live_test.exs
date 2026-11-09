defmodule TakeawayWeb.SummaryLiveTest do
  # Mutates application env, so not async.
  use TakeawayWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Notes, Questions, SpeechCreator, Summaries}

  # A cookieless test conn gets the attendee cookie-check redirect first; follow it.
  defp live_join(conn, path) do
    case live(conn, path) do
      {:error, {:redirect, %{to: to}}} -> live(conn, to)
      other -> other
    end
  end

  setup %{conn: conn} do
    organizer = organizer_fixture()
    Application.put_env(:takeaway, :llm, Takeaway.FakeLLM)
    Application.put_env(:takeaway, :llm_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:takeaway, :llm)
      Application.delete_env(:takeaway, :llm_test_pid)
    end)

    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Talk"}, [], organizer: organizer)
    {:ok, speech} = SpeechCreator.start_speech(speech)
    {:ok, attendee} = Accounts.create_anonymous_attendee()
    %{speech: speech, attendee: attendee, conn: log_in_organizer(conn, organizer)}
  end

  test "speaker ends the speech and sees the summary (generated once)", %{
    conn: conn,
    speech: speech,
    attendee: a
  } do
    {:ok, _} =
      Questions.create_question(%{text: "Why?", user_id: a.id, speech_id: speech.id})

    {:ok, lv, html} = live(conn, ~p"/speeches/#{speech.join_code}")
    assert html =~ "end-speech"
    refute html =~ "speaker-summary"

    html = lv |> element("#end-speech") |> render_click()
    assert html =~ "speaker-summary"
    refute html =~ "id=\"end-speech\""

    html = render_async(lv)
    assert html =~ "summary-text"
    assert html =~ "AI:"
    assert html =~ "Why?"
    assert html =~ "When questions spiked"
    assert Takeaway.Speeches.get_speech!(speech.id).ended_at

    # reload: served from cache, no further LLM call
    assert_received {:llm_called, _, _}
    {:ok, lv2, _} = live(conn, ~p"/speeches/#{speech.join_code}")
    assert render(lv2) =~ "summary-text"
    refute_received {:llm_called, _, _}
  end

  test "speaker summary with no transcript or questions", %{conn: conn, speech: speech} do
    {:ok, lv, _} = live(conn, ~p"/speeches/#{speech.join_code}")
    lv |> element("#end-speech") |> render_click()
    html = render_async(lv)
    assert html =~ "nothing to summarize"
    assert html =~ "No questions were asked."
    assert html =~ "No clear spike"
  end

  test "attendee sees their own cliffnotes after the speech ends", %{
    conn: conn,
    speech: speech,
    attendee: a
  } do
    {:ok, _} = Notes.create_note(%{body: "my private note", user_id: a.id, speech_id: speech.id})
    conn = Plug.Test.init_test_session(conn, user_id: a.id)

    {:ok, lv, html} = live(conn, ~p"/join/#{speech.join_code}")
    assert html =~ "The speech is live"
    refute html =~ "attendee-summary"

    {:ok, _} = SpeechCreator.end_speech(speech)
    send(lv.pid, {:speech_ended, Takeaway.Speeches.get_speech!(speech.id)})
    html = render_async(lv)
    assert html =~ "Your cliffnotes"
    assert html =~ "my private note"
    assert html =~ ~s(id="summary-announcer" role="status")
    assert html =~ "Your summary is ready."
    assert %{kind: "attendee"} = Summaries.get_attendee_summary(speech.id, a.id)
  end

  test "speaker summary is not shown to attendees", %{conn: conn, speech: speech} do
    {:ok, _} = SpeechCreator.end_speech(speech)
    {:ok, _lv, html} = live_join(conn, ~p"/join/#{speech.join_code}")
    assert html =~ "The speech has ended"
    refute html =~ "speaker-summary"
  end

  test "summaries are locked when the plan does not include them", %{
    conn: conn,
    speech: speech,
    attendee: a
  } do
    {:ok, _} = Takeaway.Billing.create_plan(%{key: "free", name: "Free", features: []})
    {:ok, speech} = SpeechCreator.end_speech(speech)

    {:ok, _lv, html} = live(conn, ~p"/speeches/#{speech.join_code}")
    assert html =~ "summary-locked"
    refute html =~ "summary-text"

    conn = Plug.Test.init_test_session(conn, %{"user_id" => a.id})
    {:ok, _lv, html} = live(conn, ~p"/join/#{speech.join_code}")
    assert html =~ "summary-locked"
    refute html =~ "cliffnotes\""
  end
end
