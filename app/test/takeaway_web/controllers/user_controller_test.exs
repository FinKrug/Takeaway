defmodule TakeawayWeb.UserControllerTest do
  use TakeawayWeb.ConnCase, async: true

  alias Takeaway.{Accounts, Notes, SpeechCreator}

  describe "register" do
    test "an attendee signs up and lands on the account page", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register",
          user: %{role: "attendee", name: "Ann", email: "ann@example.com", password: "password1"}
        )

      assert redirected_to(conn) == ~p"/account"
      user = Accounts.get_user_by_email("ann@example.com")
      assert get_session(conn, :user_id) == user.id
      assert user.role == "attendee"
      assert conn |> recycle() |> get(~p"/account") |> html_response(200) =~ "ann@example.com"
    end

    test "a speaker signs up and lands on the speaker dashboard", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register",
          user: %{role: "speaker", name: "Sam", email: "sam@example.com", password: "password1"}
        )

      assert redirected_to(conn) == ~p"/speaker"
      assert Accounts.get_user_by_email("sam@example.com").role == "speaker"
      assert conn |> recycle() |> get(~p"/speaker") |> html_response(200) =~ "Your speeches"
    end

    test "shows validation errors", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register",
          user: %{role: "speaker", name: "", email: "bad", password: "x"}
        )

      html = html_response(conn, 200)
      assert html =~ "must be a valid email"
      assert html =~ "can&#39;t be blank"
    end

    test "ignores attempts to set other fields", %{conn: conn} do
      post(conn, ~p"/users/register",
        user: %{
          role: "attendee",
          name: "Ann",
          email: "ann@example.com",
          password: "password1",
          anonymous: "true",
          password_hash: "x"
        }
      )

      user = Accounts.get_user_by_email("ann@example.com")
      refute user.anonymous
      assert String.starts_with?(user.password_hash, "pbkdf2$")
    end

    test "an anonymous attendee's row is upgraded", %{conn: conn} do
      {:ok, anon} = Accounts.create_anonymous_attendee()
      {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Talk"})
      {:ok, _} = Notes.save_note(speech.id, anon.id, "keep me")

      conn =
        conn
        |> log_in_anonymous(anon)
        |> post(~p"/users/register",
          user: %{role: "attendee", name: "Ann", email: "ann@example.com", password: "password1"}
        )

      assert redirected_to(conn) == ~p"/account"
      assert get_session(conn, :user_id) == anon.id
      user = Accounts.get_user(anon.id)
      refute user.anonymous
      assert user.email == "ann@example.com"
      assert conn |> recycle() |> get(~p"/account") |> html_response(200) =~ "Talk"
    end

    test "a plain speaker sign-up can't take an organizer-created row", %{conn: conn} do
      {:ok, placeholder} = Accounts.ensure_speaker("sam@example.com")

      conn =
        post(conn, ~p"/users/register",
          user: %{role: "speaker", name: "Sam", email: "sam@example.com", password: "password1"}
        )

      assert html_response(conn, 200) =~ "has already been taken"
      refute get_session(conn, :user_id)
      assert is_nil(Accounts.get_user!(placeholder.id).password_hash)
    end

    test "a logged-in user is sent home from the sign-up page", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")
      assert redirected_to(conn) == ~p"/account"
    end

    test "an anonymous attendee is not treated as logged in", %{conn: conn} do
      {:ok, anon} = Accounts.create_anonymous_attendee()
      conn = conn |> log_in_anonymous(anon) |> get(~p"/users/register")
      assert html_response(conn, 200) =~ "Create account"
    end
  end

  describe "login and logout" do
    test "an attendee logs in to the account page, then logs out", %{conn: conn} do
      user = user_fixture(%{email: "me@example.com", password: "password1"})

      conn =
        post(conn, ~p"/users/log_in", user: %{email: "ME@example.com", password: "password1"})

      assert redirected_to(conn) == ~p"/account"
      assert get_session(conn, :user_id) == user.id

      conn = conn |> recycle() |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      assert conn |> recycle() |> get(~p"/account") |> redirected_to() == ~p"/users/log_in"
    end

    test "a speaker logs in to the speaker dashboard", %{conn: conn} do
      user_fixture(%{role: "speaker", email: "sam@example.com", password: "password1"})

      conn =
        post(conn, ~p"/users/log_in", user: %{email: "sam@example.com", password: "password1"})

      assert redirected_to(conn) == ~p"/speaker"
    end

    test "a wrong password fails", %{conn: conn} do
      user_fixture(%{email: "me@example.com", password: "password1"})
      conn = post(conn, ~p"/users/log_in", user: %{email: "me@example.com", password: "nope"})
      assert html_response(conn, 200) =~ "Invalid email or password"
      refute get_session(conn, :user_id)
    end

    test "a passwordless speaker row can't be logged into", %{conn: conn} do
      {:ok, _} = Accounts.ensure_speaker("sam@example.com")
      conn = post(conn, ~p"/users/log_in", user: %{email: "sam@example.com", password: ""})
      assert html_response(conn, 200) =~ "Invalid email or password"
    end

    test "login renews the session", %{conn: conn} do
      user_fixture(%{email: "me@example.com", password: "password1"})

      conn =
        conn
        |> init_test_session(%{"stale" => "value"})
        |> post(~p"/users/log_in", user: %{email: "me@example.com", password: "password1"})

      refute get_session(conn, "stale")
    end

    test "login returns to the page the user was sent from", %{conn: conn} do
      user_fixture(%{email: "me@example.com", password: "password1"})
      conn = get(conn, ~p"/account")
      assert redirected_to(conn) == ~p"/users/log_in"

      conn =
        conn
        |> recycle()
        |> post(~p"/users/log_in", user: %{email: "me@example.com", password: "password1"})

      assert redirected_to(conn) == ~p"/account"
    end

    test "login never redirects to another host", %{conn: conn} do
      user_fixture(%{email: "me@example.com", password: "password1"})

      conn =
        conn
        |> init_test_session(%{"user_return_to" => "//evil.example.com"})
        |> post(~p"/users/log_in", user: %{email: "me@example.com", password: "password1"})

      assert redirected_to(conn) == ~p"/account"
    end
  end

  describe "pages" do
    test "the speaker dashboard lists the speaker's speeches with speak links", %{conn: conn} do
      speaker = user_fixture(%{role: "speaker", name: "Sam"})

      {:ok, speech} =
        SpeechCreator.create_speech(%{"title" => "Mine", "speaker_id" => speaker.id})

      {:ok, _} = SpeechCreator.create_speech(%{"title" => "Not mine"})

      html = conn |> log_in_user(speaker) |> get(~p"/speaker") |> html_response(200)
      assert html =~ "Mine"
      assert html =~ ~p"/speeches/#{speech.id}/speak"
      refute html =~ "Not mine"
    end

    test "attendees can't open the speaker dashboard", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/speaker")
      assert redirected_to(conn) == ~p"/account"
    end

    test "the speaker dashboard needs a login", %{conn: conn} do
      assert conn |> get(~p"/speaker") |> redirected_to() == ~p"/users/log_in"
    end

    test "the account page links back to joined speeches", %{conn: conn} do
      user = user_fixture()
      {:ok, speech} = SpeechCreator.create_speech(%{"title" => "Joined Talk"})
      {:ok, _} = Notes.save_note(speech.id, user.id, "hello")

      html = conn |> log_in_user(user) |> get(~p"/account") |> html_response(200)
      assert html =~ "Joined Talk"
      assert html =~ ~p"/join/#{speech.join_code}"
    end

    test "the nav shows login links, or the user's name and log out", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "nav-log-in"
      assert html =~ "nav-sign-up"

      html =
        conn
        |> log_in_user(user_fixture(%{name: "Zed Zebra"}))
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Zed Zebra"
      assert html =~ "nav-log-out"
      refute html =~ "nav-sign-up"
    end
  end

  defp log_in_anonymous(conn, user), do: log_in_user(conn, user)

  describe "speaker invite" do
    setup do
      {:ok, speaker} = Accounts.ensure_speaker("sam@example.com")
      {:ok, token} = Accounts.invite_speaker(speaker)
      %{speaker: speaker, token: token}
    end

    test "GET shows the form locked to the invited email", %{conn: conn, token: token} do
      html = conn |> get(~p"/users/invite/#{token}") |> html_response(200)
      assert html =~ "invite-form"
      assert html =~ "sam@example.com"
      assert html =~ "readonly"
    end

    test "GET with a bad token is a friendly 404", %{conn: conn} do
      html = conn |> get(~p"/users/invite/nope") |> html_response(404)
      assert html =~ "not valid"
      refute html =~ "sam@example.com"
    end

    test "POST claims the row, logs in and lands on /speaker", ctx do
      conn =
        post(ctx.conn, ~p"/users/invite/#{ctx.token}",
          user: %{name: "Sam Lee", password: "password1", email: "evil@x.com"}
        )

      assert redirected_to(conn) == ~p"/speaker"
      assert get_session(conn, :user_id) == ctx.speaker.id
      assert Accounts.get_user!(ctx.speaker.id).email == "sam@example.com"

      # The token is used up.
      again =
        post(build_conn(), ~p"/users/invite/#{ctx.token}",
          user: %{name: "X", password: "password1"}
        )

      assert html_response(again, 404) =~ "not valid"
    end

    test "POST with a short password re-renders the form", %{conn: conn, token: token} do
      conn = post(conn, ~p"/users/invite/#{token}", user: %{name: "Sam", password: "short"})
      assert html_response(conn, 200) =~ "should be at least 8"
      assert Accounts.get_invited_speaker(token)
    end

    test "POST with a wrong token fails", %{conn: conn} do
      conn = post(conn, ~p"/users/invite/bad", user: %{name: "Sam", password: "password1"})
      assert html_response(conn, 404) =~ "not valid"
      refute get_session(conn, :user_id)
    end
  end
end
