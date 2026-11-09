defmodule TakeawayWeb.OrganizerControllerTest do
  use TakeawayWeb.ConnCase, async: true

  test "register logs in and lands on the dashboard", %{conn: conn} do
    conn =
      post(conn, ~p"/organizers/register",
        organizer: %{email: "new@example.com", name: "New", password: "password1"}
      )

    assert redirected_to(conn) == ~p"/organizers"
    assert conn |> recycle() |> get(~p"/organizers") |> html_response(200) =~ "new@example.com"
  end

  test "register shows validation errors", %{conn: conn} do
    conn = post(conn, ~p"/organizers/register", organizer: %{email: "bad", password: "x"})
    assert html_response(conn, 200) =~ "must be a valid email"
  end

  test "logging out preserves a user session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"user_id" => 1, "organizer_id" => 2})
      |> delete(~p"/organizers/log_out")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_id) == 1
    refute get_session(conn, :organizer_id)
  end

  test "login with the right password, then logout", %{conn: conn} do
    organizer = organizer_fixture(%{email: "me@example.com", password: "password1"})

    conn =
      post(conn, ~p"/organizers/log_in",
        organizer: %{email: "me@example.com", password: "password1"}
      )

    assert redirected_to(conn) == ~p"/organizers"
    assert get_session(conn, :organizer_id) == organizer.id

    conn = conn |> recycle() |> delete(~p"/organizers/log_out")
    assert redirected_to(conn) == ~p"/"
    assert conn |> recycle() |> get(~p"/organizers") |> redirected_to() == ~p"/organizers/log_in"
  end

  test "login with a wrong password fails", %{conn: conn} do
    organizer_fixture(%{email: "me@example.com", password: "password1"})

    conn =
      post(conn, ~p"/organizers/log_in", organizer: %{email: "me@example.com", password: "nope"})

    assert html_response(conn, 200) =~ "Invalid email or password"
    refute get_session(conn, :organizer_id)
  end

  test "login returns to the page the organizer was sent from", %{conn: conn} do
    organizer_fixture(%{email: "me@example.com", password: "password1"})

    conn = get(conn, ~p"/speeches/new")
    assert redirected_to(conn) == ~p"/organizers/log_in"

    conn =
      conn
      |> recycle()
      |> post(~p"/organizers/log_in",
        organizer: %{email: "me@example.com", password: "password1"}
      )

    assert redirected_to(conn) == ~p"/speeches/new"
  end

  test "the home page links to login, or to the dashboard when logged in", %{conn: conn} do
    assert conn |> get(~p"/") |> html_response(200) =~ "Organizer log in"

    html = conn |> log_in_organizer(organizer_fixture()) |> get(~p"/") |> html_response(200)
    assert html =~ "Your events and tickets"
  end
end
