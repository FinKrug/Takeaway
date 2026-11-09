defmodule TakeawayWeb.AttendeeSessionTest do
  use TakeawayWeb.ConnCase, async: true

  import Ecto.Query

  alias Takeaway.{Repo, SpeechCreator, Tickets}
  alias Takeaway.Accounts.User

  defp attendee_count,
    do: Repo.aggregate(from(u in User, where: u.role == "attendee"), :count)

  defp location(conn) do
    [to] = get_resp_header(conn, "location")
    uri = URI.parse(to)
    {uri.path, URI.decode_query(uri.query || "")}
  end

  # Walks the cookie check like a browser that keeps cookies; returns the final conn.
  defp join_with_cookies(conn, path) do
    conn = get(conn, path)
    assert conn.status == 302
    {to_path, query} = location(conn)
    conn = conn |> recycle() |> get(to_path <> "?" <> URI.encode_query(query))
    assert conn.status == 302
    {to_path, query} = location(conn)
    conn |> recycle() |> get(to_path <> "?" <> URI.encode_query(query))
  end

  setup do
    {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Talk"}, [], event: {:new, "Conf"})
    %{speech: speech}
  end

  test "first visit redirects with cookie_check, keeping the ticket, and creates no user",
       %{conn: conn, speech: speech} do
    {:ok, ticket} = Tickets.create_ticket(Takeaway.Events.get_event!(speech.event_id))
    before = attendee_count()

    conn = get(conn, ~p"/join/#{speech.join_code}?ticket=#{ticket.code}")
    assert conn.status == 302
    path = "/join/#{speech.join_code}"
    assert {^path, %{"ticket" => code, "cookie_check" => "1"}} = location(conn)
    assert code == ticket.code
    assert get_session(conn, :user_id) == nil
    assert attendee_count() == before

    # Coming back with the cookie: one user, then a redirect that drops cookie_check.
    conn = conn |> recycle() |> get("#{path}?cookie_check=1&ticket=#{ticket.code}")
    assert conn.status == 302
    assert {^path, %{"ticket" => ^code} = query} = location(conn)
    refute Map.has_key?(query, "cookie_check")
    id = get_session(conn, :user_id)
    assert %User{anonymous: true, role: "attendee"} = Repo.get(User, id)
    assert attendee_count() == before + 1

    conn = conn |> recycle() |> get("#{path}?ticket=#{ticket.code}")
    assert conn.status == 200
    assert get_session(conn, :user_id) == id
  end

  test "the attendee is reused on reload and on other speeches", %{conn: conn, speech: speech} do
    before = attendee_count()
    conn = join_with_cookies(conn, ~p"/join/#{speech.join_code}")
    assert conn.status == 200
    id = get_session(conn, :user_id)
    assert is_integer(id)

    {:ok, other} = SpeechCreator.create_speech(%{"title" => "Other"})
    conn = conn |> recycle() |> get(~p"/join/#{speech.join_code}")
    assert conn.status == 200
    assert get_session(conn, :user_id) == id
    conn = conn |> recycle() |> get(~p"/join/#{other.join_code}")
    assert conn.status == 200
    assert get_session(conn, :user_id) == id
    assert attendee_count() == before + 1
  end

  test "a session pointing to a deleted user gets a new attendee", %{conn: conn, speech: speech} do
    conn = join_with_cookies(conn, ~p"/join/#{speech.join_code}")
    id = get_session(conn, :user_id)
    Repo.delete!(Repo.get!(User, id))

    conn = conn |> recycle() |> get(~p"/join/#{speech.join_code}")
    assert conn.status == 200
    new_id = get_session(conn, :user_id)
    assert is_integer(new_id) and new_id != id
  end

  test "cookies that never come back: no user, read-only page", %{speech: speech} do
    before = attendee_count()

    conn = get(build_conn(), ~p"/join/#{speech.join_code}?cookie_check=1")
    assert conn.status == 200
    assert get_session(conn, :user_id) == nil
    assert html_response(conn, 200) =~ "notes-unavailable"

    # A client that keeps dropping cookies creates nothing, however often it loops.
    for _ <- 1..5 do
      assert get(build_conn(), ~p"/join/#{speech.join_code}").status == 302
      assert get(build_conn(), ~p"/join/#{speech.join_code}?cookie_check=1").status == 200
    end

    assert attendee_count() == before
  end

  test "no user and no redirect for crawlers, unknown codes or a missing ticket",
       %{conn: conn, speech: speech} do
    before = attendee_count()

    bot =
      conn
      |> put_req_header("user-agent", "Slackbot-LinkExpanding 1.0")
      |> get(~p"/join/#{speech.join_code}")

    assert bot.status == 200
    assert get_session(bot, :user_id) == nil

    unknown = get(build_conn(), ~p"/join/NOPE00")
    assert unknown.status == 200
    assert get_session(unknown, :user_id) == nil

    {:ok, _ticket} = Tickets.create_ticket(Takeaway.Events.get_event!(speech.event_id))
    gated = get(build_conn(), ~p"/join/#{speech.join_code}")
    assert gated.status == 200
    assert get_session(gated, :user_id) == nil

    assert attendee_count() == before
  end
end
