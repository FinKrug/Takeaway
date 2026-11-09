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
    test "shows the role of whoever is signed in", %{conn: conn} do
      speaker = user_fixture(%{role: "speaker", name: "Sally Speaker"})
      html = conn |> log_in_user(speaker) |> get(~p"/") |> html_response(200)
      assert html =~ ~r/role-badge.*?Speaker/s
      assert html =~ "Your speeches"

      attendee = user_fixture(%{name: "Andy"})
      html = build_conn() |> log_in_user(attendee) |> get(~p"/") |> html_response(200)
      assert html =~ ~r/role-badge.*?Attendee/s
      assert html =~ "Your talks"

      organizer = organizer_fixture()
      html = build_conn() |> log_in_organizer(organizer) |> get(~p"/") |> html_response(200)
      assert html =~ ~r/role-badge.*?Organizer/s
      assert html =~ "Your conferences"
      assert html =~ "nav-organizer-log-out"
    end

    test "an organizer also signed in as a speaker sees both roles", %{conn: conn} do
      html =
        conn
        |> log_in_organizer(organizer_fixture())
        |> log_in_user(user_fixture(%{role: "speaker", name: "Both"}))
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "nav-organizer-identity"
      assert html =~ "nav-user-identity"
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
      _other = speech(title: "Someone else's")

      html = conn |> log_in_user(speaker) |> get(~p"/speaker") |> html_response(200)

      assert html =~ "ElixirConf"
      assert html =~ "Standalone talks"
      assert html =~ "Live Talk"
      assert html =~ "Next Talk"
      refute html =~ "Someone else&#39;s"
      assert html =~ "live-now-#{live.id}"
      assert html =~ "Live now"
      assert html =~ "Upcoming"
      assert html =~ "To give"
      assert html =~ next.join_code
      assert html =~ ~p"/speeches/#{next.id}/speak"
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

      html = conn |> log_in_user(user) |> get(~p"/account") |> html_response(200)
      assert html =~ "RubyConf"
      assert html =~ "2 questions"
      assert html =~ "notes"
      assert html =~ "Review"
      assert html =~ ~r/role-badge.*?Attendee/s
    end
  end

  describe "organizer home" do
    test "lists conferences with their speeches and speakers, and standalone talks", %{
      conn: conn
    } do
      organizer = organizer_fixture()
      {:ok, conf} = Events.create_event(%{name: "My Conf"}, organizer)
      {:ok, _empty} = Events.create_event(%{name: "Empty Conf"}, organizer)
      speaker = user_fixture(%{role: "speaker", name: "Sally"})
      in_conf = speech(%{title: "Conf Talk", event_id: conf.id, speaker_id: speaker.id})
      solo = speech(%{title: "My Solo Talk"}, organizer)
      _not_mine = speech(%{title: "Not Mine"})

      assert organizer
             |> Speeches.list_speeches_for_organizer()
             |> Enum.map(& &1.id)
             |> Enum.sort() ==
               Enum.sort([in_conf.id, solo.id])

      html = conn |> log_in_organizer(organizer) |> get(~p"/organizers") |> html_response(200)
      assert html =~ "My Conf"
      assert html =~ "Empty Conf"
      assert html =~ "No speeches in this conference yet."
      assert html =~ "Conf Talk"
      assert html =~ "Sally"
      assert html =~ "My Solo Talk"
      assert html =~ "No speaker yet"
      refute html =~ "Not Mine"
      assert html =~ ~p"/speeches/#{in_conf.join_code}"
      assert html =~ Events.tickets_path(conf)
    end
  end
end
