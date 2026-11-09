defmodule TakeawayWeb.OrganizerAuth do
  @moduledoc """
  Organizer login: plugs for the router and an `on_mount` hook for LiveViews.

  The signed session cookie holds only the organizer id. Pages that need an
  organizer use the `:require_organizer` plug (redirects to the login page and
  remembers where to come back to) and the `:require_organizer` on_mount hook
  (which also covers LiveView reconnects).
  """
  import Plug.Conn
  import Phoenix.Controller
  use Phoenix.VerifiedRoutes, endpoint: TakeawayWeb.Endpoint, router: TakeawayWeb.Router

  alias Takeaway.Organizers

  @doc "Starts a fresh session for `organizer` and redirects to where they were headed."
  def log_in(conn, organizer) do
    return_to = get_session(conn, :organizer_return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:organizer_id, organizer.id)
    |> redirect(to: safe_path(return_to) || ~p"/organizers")
  end

  @doc """
  Logs out this role only: a new session id, without :organizer_id. Someone also signed in as
  a speaker or attendee stays signed in as that.
  """
  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:organizer_id)
    |> delete_session(:organizer_return_to)
    |> redirect(to: ~p"/")
  end

  @doc "Plug: assigns `:current_organizer` (or nil) from the session."
  def fetch_current_organizer(conn, _opts) do
    organizer =
      case get_session(conn, :organizer_id) do
        id when is_integer(id) -> Organizers.get_organizer(id)
        _ -> nil
      end

    assign(conn, :current_organizer, organizer)
  end

  @doc "Plug: halts with a redirect to the login page unless an organizer is logged in."
  def require_organizer(%{assigns: %{current_organizer: %{}}} = conn, _opts), do: conn

  def require_organizer(conn, _opts) do
    conn
    |> maybe_store_return_to()
    |> put_flash(:error, "Log in to continue")
    |> redirect(to: ~p"/organizers/log_in")
    |> halt()
  end

  @doc "Plug: sends a logged-in organizer to their dashboard (for the login/register pages)."
  def redirect_if_organizer(%{assigns: %{current_organizer: %{}}} = conn, _opts),
    do: conn |> redirect(to: ~p"/organizers") |> halt()

  def redirect_if_organizer(conn, _opts), do: conn

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    path =
      conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

    put_session(conn, :organizer_return_to, path)
  end

  defp maybe_store_return_to(conn), do: conn

  # Only local paths: never redirect to another host.
  @doc false
  def safe_path("/" <> _ = path) do
    if String.starts_with?(path, "//") or String.contains?(path, "\\"), do: nil, else: path
  end

  def safe_path(_), do: nil

  @doc "LiveView hook: assigns `:current_organizer`, redirecting to the login page if missing."
  def on_mount(:require_organizer, _params, session, socket) do
    organizer =
      case session["organizer_id"] do
        id when is_integer(id) -> Organizers.get_organizer(id)
        _ -> nil
      end

    if organizer do
      {:cont, Phoenix.Component.assign(socket, :current_organizer, organizer)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/organizers/log_in")}
    end
  end
end
