defmodule TakeawayWeb.AttendeeSession do
  @moduledoc """
  Plug for `/join/:code`: gives every attendee an anonymous identity.

  A LiveView can't write the session cookie, so this runs on the plain HTTP request
  before `SpeechLive.Join` mounts. The attendee
  (`Takeaway.Accounts.create_anonymous_attendee/0`) is stored as `"user_id"` in the signed
  session cookie; later visits, to this or any other speech, reuse it. If the stored id no
  longer points to an attendee (deleted user), a new one is created.

  Users are only created for browsers that keep cookies, so clients that drop them can't
  create unbounded rows:

    1. First visit without a session: no user yet. The plug sets `cookie_ok` in the session
       and redirects (302) to the same URL (query params such as `ticket` kept) plus
       `cookie_check=1`.
    2. The browser comes back with `cookie_ok`: the attendee is created and the plug
       redirects once more to the URL without `cookie_check`.
    3. A request with `cookie_check` but without `cookie_ok`: cookies are not coming back.
       Nothing is created; the page renders in its read-only "cookies off" state.

  No user is created (and no redirect happens) for crawlers and link previews, for unknown
  join codes, or when the event needs a ticket the request doesn't carry. The page still
  renders for them, just without notes and questions.
  """
  import Plug.Conn

  alias Takeaway.{Accounts, Speeches, Tickets}

  @check_param "cookie_check"

  # Link unfurlers and crawlers that open shared join links.
  @bot_pattern ~r/bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|whatsapp|telegram|discord|skype|curl|wget|python-requests|headless/i

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_session() |> fetch_query_params()

    cond do
      current_attendee(conn) -> conn
      bot?(conn) -> conn
      not joinable?(conn) -> conn
      get_session(conn, :cookie_ok) -> create_attendee(conn)
      Map.has_key?(conn.query_params, @check_param) -> conn
      true -> start_cookie_check(conn)
    end
  end

  defp current_attendee(conn) do
    with id when is_integer(id) <- get_session(conn, :user_id),
         %{role: "attendee"} = user <- Accounts.get_user(id) do
      user
    else
      _ -> nil
    end
  end

  defp bot?(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> Regex.match?(@bot_pattern, ua)
      [] -> false
    end
  end

  defp joinable?(%{path_params: %{"code" => code}} = conn) do
    case Speeches.get_speech_by_join_code(code) do
      nil -> false
      speech -> Tickets.validate_for_event(speech.event_id, conn.params["ticket"]) == :ok
    end
  end

  defp joinable?(_conn), do: false

  defp start_cookie_check(conn) do
    conn
    |> put_session(:cookie_ok, true)
    |> redirect_to(Map.put(conn.query_params, @check_param, "1"))
  end

  defp create_attendee(conn) do
    case Accounts.create_anonymous_attendee() do
      {:ok, user} ->
        conn = put_session(conn, :user_id, user.id)

        # Drop the check param from the URL, so a copied link starts clean.
        if Map.has_key?(conn.query_params, @check_param),
          do: redirect_to(conn, Map.delete(conn.query_params, @check_param)),
          else: conn

      {:error, _} ->
        conn
    end
  end

  defp redirect_to(conn, params) do
    query = if params == %{}, do: "", else: "?" <> Plug.Conn.Query.encode(params)

    conn
    |> Phoenix.Controller.redirect(to: conn.request_path <> query)
    |> halt()
  end
end
