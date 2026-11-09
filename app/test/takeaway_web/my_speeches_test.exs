defmodule TakeawayWeb.MySpeechesTest do
  @moduledoc """
  Each role can tell which role it is signed in as and find its conferences and speeches:
  the account strip's role badge, and the organizer, speaker and attendee home pages.
  """
  use TakeawayWeb.ConnCase, async: true

  alias Takeaway.{Accounts, Events, Notes, Questions, Speeches}
  alias Takeaway.Speeches.Speech
  alias TakeawayWeb.SpeechList

  @now ~U[2026-11-09 12:00:00Z]

  defp doc(html), do: LazyHTML.from_document(html)

  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text() |> squish()

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp present?(doc, sel), do: doc |> LazyHTML.query(sel) |> Enum.count() > 0

  defp hrefs(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.attribute("href")

  defp speech(attrs, organizer \\ nil) do
    {:ok, speech} = Speeches.create_speech(Map.new(attrs), organizer)
    Takeaway.Repo.preload(speech, [:event, :speaker])
  end

  describe "Speech.status/1" do
    test "upcoming, live and ended" do
      assert Speech.status(%Speech{}) == :upcoming
      assert Speech.status(%Speech{started_at: @now}) == :live
      assert Speech.status(%Speech{started_at: @now, ended_at: @now}) == :ended
    end
  end

  describe "SpeechList.group_by_conference/2" do
    test "groups by conference, live first, standalone last, empty conferences kept" do
      {:ok, conf_a} = Events.create_event(%{name: "Conf A"})
      {:ok, conf_b} = Events.create_event(%{name: "Conf B"})
      {:ok, empty} = Events.create_event(%{name: "Empty Conf"})

      ended = speech(title: "A ended", event_id: conf_a.id, started_at: @now, ended_at: @now)
      upcoming = speech(title: "A upcoming", event_id: conf_a.id)
      live = speech(title: "B live", event_id: conf_b.id, started_at: @now)
      solo = speech(title: "Solo", started_at: @now)

      groups = SpeechList.group_by_conference([ended, upcoming, live, solo], [conf_a, empty])

      assert Enum.map(groups, fn {e, list} -> {e && e.name, Enum.map(list, & &1.title)} end) ==
               [
                 {"Conf B", ["B live"]},
                 {"Conf A", ["A upcoming", "A ended"]},
                 {"Empty Conf", []},
                 {nil, ["Solo"]}
               ]

      assert SpeechList.status_counts([ended, upcoming, live, solo]) ==
               %{live: 2, upcoming: 1, ended: 1}
    end
  end

  describe "account strip" do
    test "shows the role of whoever is signed in, linking to that role's home", %{conn: conn} do
      speaker = user_fixture(%{role: "speaker", name: "Sally Speaker"})
      d = conn |> log_in_user(speaker) |> get(~p"/") |> html_response(200) |> doc()
      assert text(d, "#nav-user-identity .role-badge") == "Speaker"
      assert text(d, "#nav-user-name") == "Sally Speaker"
      assert hrefs(d, "#nav-account") == [~p"/speaker"]
      refute present?(d, "#nav-organizer-identity")

      attendee = user_fixture(%{name: "Andy"})
      d = build_conn() |> log_in_user(attendee) |> get(~p"/") |> html_response(200) |> doc()
      assert text(d, "#nav-user-identity .role-badge") == "Attendee"
      assert hrefs(d, "#nav-account") == [~p"/account"]

      organizer = organizer_fixture()
      d = build_conn() |> log_in_organizer(organizer) |> get(~p"/") |> html_response(200) |> doc()
      assert text(d, "#nav-organizer-identity .role-badge") == "Organizer"
      assert hrefs(d, "#nav-organizer") == [~p"/organizers"]
      assert hrefs(d, "#nav-organizer-log-out") == [~p"/organizers/log_out"]
      refute present?(d, "#nav-user-identity")
      refute present?(d, "#nav-log-in")
    end

    test "with two roles signed in, each Log out ends only its own role", %{conn: conn} do
      organizer = organizer_fixture()
      speaker = user_fixture(%{role: "speaker", name: "Both"})
      conn = conn |> log_in_organizer(organizer) |> log_in_user(speaker)

      d = conn |> get(~p"/") |> html_response(200) |> doc()
      assert present?(d, "#nav-organizer-identity")
      assert present?(d, "#nav-user-identity")

      conn = conn |> delete(~p"/users/log_out")
      assert get_session(conn, :organizer_id) == organizer.id
      assert get_session(conn, :user_id) == nil

      d = conn |> recycle() |> get(~p"/") |> html_response(200) |> doc()
      assert present?(d, "#nav-organizer-identity")
      refute present?(d, "#nav-user-identity")

      conn =
        build_conn()
        |> log_in_organizer(organizer)
        |> log_in_user(speaker)
        |> delete(~p"/organizers/log_out")

      assert get_session(conn, :organizer_id) == nil
      assert get_session(conn, :user_id) == speaker.id
    end
  end

  describe "speaker home" do
    test "lists talks to give by conference, with status, code and a live callout", %{
      conn: conn
    } do
      speaker = user_fixture(%{role: "speaker", name: "Sally"})
      {:ok, conf} = Events.create_event(%{name: "ElixirConf"})

      live =
        speech(title: "Live Talk", event_id: conf.id, speaker_id: speaker.id, started_at: @now)

      next = speech(title: "Next Talk", speaker_id: speaker.id)
      other = speech(title: "Someone else's")

      d = conn |> log_in_user(speaker) |> get(~p"/speaker") |> html_response(200) |> doc()

      assert text(d, "#role .role-badge") == "Speaker"
      assert text(d, "#conference-#{conf.id}-name") =~ "ElixirConf"
      assert present?(d, "#conference-#{conf.id} #speech-#{live.id}")
      assert present?(d, "#standalone #speech-#{next.id}")
      refute present?(d, "#speech-#{other.id}")

      assert present?(d, "#speech-#{live.id} .status-live")
      assert present?(d, "#speech-#{next.id} .status-upcoming")
      assert text(d, "#speech-#{next.id} .join-code") == next.join_code
      assert hrefs(d, "#speech-#{next.id} .speak-link") == [~p"/speeches/#{next.id}/speak"]

      assert present?(d, "#live-now-#{live.id}")
      refute present?(d, "#live-now-#{next.id}")
      assert text(d, "#count-upcoming") == "To give 1"
      assert text(d, "#count-live") == "Live now 1"
    end
  end

  describe "attendee home" do
    test "lists attended talks by conference, with what the attendee left", %{conn: conn} do
      user = user_fixture(%{name: "Andy"})
      {:ok, conf} = Events.create_event(%{name: "RubyConf"})
      talk = speech(title: "Asked Here", event_id: conf.id, started_at: @now)
      noted = speech(title: "Noted Here", started_at: @now, ended_at: @now)

      {:ok, _} = Questions.create_question(%{text: "Why?", speech_id: talk.id, user_id: user.id})
      {:ok, _} = Questions.create_question(%{text: "How?", speech_id: talk.id, user_id: user.id})
      {:ok, _} = Notes.save_note(noted.id, user.id, "good stuff")

      assert Accounts.attendee_activity(user) == %{
               talk.id => %{questions: 2, note?: false},
               noted.id => %{questions: 0, note?: true}
             }

      d = conn |> log_in_user(user) |> get(~p"/account") |> html_response(200) |> doc()

      assert text(d, "#role .role-badge") == "Attendee"
      assert present?(d, "#conference-#{conf.id} #speech-#{talk.id}")
      assert present?(d, "#standalone #speech-#{noted.id}")
      assert text(d, "#speech-#{talk.id} .activity") == "2 questions"
      assert text(d, "#speech-#{noted.id} .activity") == "notes"
      assert present?(d, "#speech-#{noted.id} .status-ended")
      assert text(d, "#speech-#{noted.id} .join-link") == "Review"
      assert text(d, "#speech-#{talk.id} .join-link") == "Open"
    end
  end

  describe "organizer home" do
    test "lists conferences with their speeches and speakers, and standalone talks", %{
      conn: conn
    } do
      organizer = organizer_fixture()
      {:ok, conf} = Events.create_event(%{name: "My Conf"}, organizer)
      {:ok, empty} = Events.create_event(%{name: "Empty Conf"}, organizer)
      speaker = user_fixture(%{role: "speaker", name: "Sally"})
      in_conf = speech(%{title: "Conf Talk", event_id: conf.id, speaker_id: speaker.id})
      solo = speech(%{title: "My Solo Talk"}, organizer)
      not_mine = speech(%{title: "Not Mine"})

      assert organizer
             |> Speeches.list_speeches_for_organizer()
             |> Enum.map(& &1.id)
             |> Enum.sort() == Enum.sort([in_conf.id, solo.id])

      d =
        conn |> log_in_organizer(organizer) |> get(~p"/organizers") |> html_response(200) |> doc()

      assert text(d, "#role .role-badge") == "Organizer"
      assert present?(d, "#conference-#{conf.id} #speech-#{in_conf.id}")
      assert text(d, "#speech-#{in_conf.id} .speaker-name") == "Sally"
      assert present?(d, "#standalone #speech-#{solo.id}")
      assert text(d, "#speech-#{solo.id} .speaker-name") == "No speaker yet"
      refute present?(d, "#speech-#{not_mine.id}")

      assert text(d, "#conference-#{empty.id}") =~ "No speeches in this conference yet."
      assert hrefs(d, "#conference-#{conf.id} .tickets-link") == [Events.tickets_path(conf)]

      assert hrefs(d, "#speech-#{in_conf.id} .manage-link") == [
               ~p"/speeches/#{in_conf.join_code}"
             ]
    end
  end
end
