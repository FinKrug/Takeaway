defmodule TakeawayWeb.UserAuth do
  @moduledoc """
  Speaker and attendee login: plugs for the router and `on_mount` hooks for LiveViews
  (mirrors `TakeawayWeb.OrganizerAuth`).

  The signed session cookie holds only the user id under `:user_id`, the same key
  `TakeawayWeb.AttendeeSession` uses for anonymous attendees. So a logged-in attendee's
  notes and questions belong to their account. An anonymous attendee is *not* a logged-in
  user: `:current_user` stays `nil` for rows with `anonymous: true`.

  Logging in renews the session (against session fixation) and returns to a remembered
  local path, else to the speaker dashboard or the attendee account page.
  """
  import Plug.Conn
  import Phoenix.Controller
  use Phoenix.VerifiedRoutes, endpoint: TakeawayWeb.Endpoint, router: TakeawayWeb.Router

  alias Takeaway.Accounts
  alias TakeawayWeb.OrganizerAuth

  @doc "Starts a fresh session for `user` and redirects to where they were headed."
  def log_in(conn, user) do
    return_to = get_session(conn, :user_return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_id, user.id)
    |> redirect(to: OrganizerAuth.safe_path(return_to) || home_path(user))
  end

  @doc """
  Logs out this role only: a new session id, without :user_id. Someone also signed in as
  an organizer stays signed in as that.
  """
  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:user_id)
    |> delete_session(:user_return_to)
    |> redirect(to: ~p"/")
  end

  def home_path(%{role: "speaker"}), do: ~p"/speaker"
  def home_path(_user), do: ~p"/account"

  @doc "The logged-in (non-anonymous) user for a session id, or nil."
  def user_from_session(id) when is_integer(id) do
    case Accounts.get_user(id) do
      %{anonymous: false} = user -> user
      _ -> nil
    end
  end

  def user_from_session(_), do: nil

  @doc "Plug: assigns `:current_user` (or nil) from the session."
  def fetch_current_user(conn, _opts),
    do: assign(conn, :current_user, user_from_session(get_session(conn, :user_id)))

  @doc "Plug: halts with a redirect to the login page unless a user is logged in."
  def require_user(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn
  def require_user(conn, _opts), do: deny(conn, ~p"/users/log_in")

  @doc "Plug: like `require_user`, and the user must be a speaker."
  def require_speaker(%{assigns: %{current_user: %{role: "speaker"}}} = conn, _opts), do: conn

  def require_speaker(%{assigns: %{current_user: %{}}} = conn, _opts),
    do:
      conn
      |> put_flash(:error, "That page is for speakers")
      |> redirect(to: ~p"/account")
      |> halt()

  def require_speaker(conn, _opts), do: deny(conn, ~p"/users/log_in")

  @doc """
  Plug for the speaker page: an organizer or a speaker must be logged in (which speech they
  may open is checked by the page itself).
  """
  def require_organizer_or_speaker(%{assigns: assigns} = conn, _opts) do
    case assigns do
      %{current_organizer: %{}} -> conn
      %{current_user: %{role: "speaker"}} -> conn
      _ -> deny(conn, ~p"/users/log_in", [:organizer_return_to, :user_return_to])
    end
  end

  @doc "Plug: sends a logged-in user to their home page (for the login/register pages)."
  def redirect_if_user(%{assigns: %{current_user: %{} = user}} = conn, _opts),
    do: conn |> redirect(to: home_path(user)) |> halt()

  def redirect_if_user(conn, _opts), do: conn

  defp deny(conn, path, keys \\ [:user_return_to]) do
    conn
    |> maybe_store_return_to(keys)
    |> put_flash(:error, "Log in to continue")
    |> redirect(to: path)
    |> halt()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn, keys) do
    path =
      conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

    Enum.reduce(keys, conn, &put_session(&2, &1, path))
  end

  defp maybe_store_return_to(conn, _keys), do: conn

  @doc """
  LiveView hooks.

    * `:mount_current_user` assigns `:current_user` (nil when logged out).
    * `:require_organizer_or_speaker` also assigns `:current_organizer` and halts to the
      login page unless one of them is present. It re-reads both from the session on every
      mount (so on every reconnect).
  """
  def on_mount(:mount_current_user, _params, session, socket),
    do:
      {:cont,
       Phoenix.Component.assign(socket, :current_user, user_from_session(session["user_id"]))}

  def on_mount(:require_organizer_or_speaker, _params, session, socket) do
    organizer =
      case session["organizer_id"] do
        id when is_integer(id) -> Takeaway.Organizers.get_organizer(id)
        _ -> nil
      end

    user =
      case user_from_session(session["user_id"]) do
        %{role: "speaker"} = u -> u
        _ -> nil
      end

    if organizer || user do
      {:cont,
       socket
       |> Phoenix.Component.assign(:current_organizer, organizer)
       |> Phoenix.Component.assign(:current_user, user)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/users/log_in")}
    end
  end
end
