defmodule TakeawayWeb.AttendeeSessionTest do
  use TakeawayWeb.ConnCase, async: true

  import Ecto.Query

  alias Takeaway.{Repo, SpeechCreator, Tickets}
  alias Takeaway.Accounts.User

  defp attendee_count,
    do: Repo.aggregate(from(u in User, where: u.role == "attendee"), :count)

  setup do
    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Talk"})
    %{speech: speech}
  end

  test "first visit creates one anonymous attendee and reuses it", %{conn: conn, speech: speech} do
    before = attendee_count()

    conn = get(conn, ~p"/join/#{speech.join_code}")
    id = get_session(conn, :user_id)
    assert is_integer(id)
    assert %User{anonymous: true, role: "attendee"} = Repo.get(User, id)
    assert attendee_count() == before + 1

    # Reload and another speech: same user, no new row.
    {:ok, other} = SpeechCreator.create_speech(%{"title" => "Other"})
    conn = conn |> recycle() |> get(~p"/join/#{speech.join_code}")
    assert get_session(conn, :user_id) == id
    conn = conn |> recycle() |> get(~p"/join/#{other.join_code}")
    assert get_session(conn, :user_id) == id
    assert attendee_count() == before + 1
  end

  test "a session pointing to a deleted user gets a new attendee", %{conn: conn, speech: speech} do
    conn = get(conn, ~p"/join/#{speech.join_code}")
    id = get_session(conn, :user_id)
    Repo.delete!(Repo.get!(User, id))

    conn = conn |> recycle() |> get(~p"/join/#{speech.join_code}")
    new_id = get_session(conn, :user_id)
    assert is_integer(new_id) and new_id != id
  end

  test "no user for crawlers, unknown codes or a missing ticket", %{conn: conn, speech: speech} do
    before = attendee_count()

    bot =
      conn
      |> put_req_header("user-agent", "Slackbot-LinkExpanding 1.0")
      |> get(~p"/join/#{speech.join_code}")

    assert get_session(bot, :user_id) == nil

    unknown = get(build_conn(), ~p"/join/NOPE00")
    assert get_session(unknown, :user_id) == nil

    {:ok, _ticket} = Tickets.create_ticket(Takeaway.Events.get_event!(speech.event_id))
    gated = get(build_conn(), ~p"/join/#{speech.join_code}")
    assert get_session(gated, :user_id) == nil

    assert attendee_count() == before
  end
end
