defmodule Takeaway.Events do
  @moduledoc "Events, which group speeches."
  import Ecto.Query
  alias Takeaway.Events.Event
  alias Takeaway.Repo

  def list_events, do: Repo.all(from e in Event, order_by: [desc: e.inserted_at, desc: e.id])

  def get_event(id), do: Repo.get(Event, id)
  def get_event!(id), do: Repo.get!(Event, id)
  def get_event_by_join_code(code), do: Repo.get_by(Event, join_code: String.upcase(code))

  @doc """
  The event with `id`, only when `token` matches its admin token (constant-time compare).
  Returns `nil` for a missing event or a wrong token, so callers can't tell them apart.
  """
  def get_event_for_admin(id, token) when is_binary(token) do
    with {int, ""} <- Integer.parse(to_string(id)),
         %Event{admin_token: expected} = event when is_binary(expected) <- get_event(int),
         true <- Plug.Crypto.secure_compare(expected, token) do
      event
    else
      _ -> nil
    end
  end

  def get_event_for_admin(_id, _token), do: nil

  @doc "Organizer link to the event's tickets page (contains the secret admin token)."
  def tickets_path(%Event{id: id, admin_token: token}),
    do: "/events/#{id}/tickets?" <> URI.encode_query(token: token)

  def create_event(attrs), do: %Event{} |> Event.changeset(attrs) |> Repo.insert()

  def update_event(%Event{} = event, attrs), do: event |> Event.changeset(attrs) |> Repo.update()
end
