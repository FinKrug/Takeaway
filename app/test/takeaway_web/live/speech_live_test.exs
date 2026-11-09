defmodule TakeawayWeb.SpeechLiveTest do
  use TakeawayWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Takeaway.{Speeches, SpeechCreator}

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

    [speech] = Takeaway.Repo.all(Takeaway.Speeches.Speech)
    assert speech.tags == ["elixir", "liveview"]

    assert [%{kind: "plan", content: "# Plan\nhello"} = a, %{kind: "slides"}] =
             Speeches.list_artifacts(speech.id)

    assert File.exists?(Path.join(SpeechCreator.uploads_dir(), a.url))
    assert html =~ speech.join_code
    assert html =~ "/join/#{speech.join_code}"

    SpeechCreator.subscribe(speech.id)
    html = show |> element("#start-speech") |> render_click()
    assert html =~ "leaderboard-panel"
    refute html =~ "id=\"start-speech\""
    assert_receive {:speech_started, %{started_at: %DateTime{}}}
    assert Speeches.get_speech!(speech.id).started_at
  end

  test "title is required", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/speeches/new")
    html = lv |> form("#speech-form", speech: %{title: " "}) |> render_submit()
    assert html =~ "can&#39;t be blank"
  end

  test "join page reflects start over PubSub", %{conn: conn} do
    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "T"})
    {:ok, lv, html} = live(conn, ~p"/join/#{speech.join_code}")
    assert html =~ "Waiting"
    {:ok, _} = SpeechCreator.start_speech(speech)
    assert render(lv) =~ "The speech is live"
  end

  test "unknown join code", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/join/NOPE00")
    assert html =~ "No speech found"
  end

  test "artifact download", %{conn: conn} do
    {:ok, speech} =
      SpeechCreator.create_speech(%{"title" => "T"}, [{"plan", "p.txt", __ENV__.file}])

    [a] = Speeches.list_artifacts(speech.id)
    assert get(conn, ~p"/artifacts/#{a.id}").status == 200
    assert get(conn, ~p"/artifacts/0").status == 404
  end
end
