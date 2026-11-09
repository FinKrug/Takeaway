defmodule TakeawayWeb.AttendeeSession do
  @moduledoc """
  Plug for `/join/:code`: gives every attendee an anonymous identity.

  A LiveView can't write the session cookie, so this runs on the plain HTTP request
  before `SpeechLive.Join` mounts. The first visit creates an anonymous attendee
  (`Takeaway.Accounts.create_anonymous_attendee/0`) and stores its id as `"user_id"` in
  the signed session cookie; later visits, to this or any other speech, reuse it. If the
  stored id no longer points to an attendee (deleted user), a new one is created.

  To keep junk rows down, no user is created for crawlers and link previews, for unknown
  join codes, or when the event needs a ticket the request doesn't carry. The page still
  renders for them, just without notes and questions.
  """
  import Plug.Conn

  alias Takeaway.{Accounts, Speeches, Tickets}

  # Link unfurlers and crawlers that open shared join links.
  @bot_pattern ~r/bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|whatsapp|telegram|discord|skype|curl|wget|python-requests|headless/i

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_session(conn)

    cond do
      current_attendee(conn) -> conn
      bot?(conn) -> conn
      joinable?(conn) -> create_attendee(conn)
      true -> conn
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

  defp create_attendee(conn) do
    case Accounts.create_anonymous_attendee() do
      {:ok, user} -> put_session(conn, :user_id, user.id)
      {:error, _} -> conn
    end
  end
end
