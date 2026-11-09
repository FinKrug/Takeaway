defmodule Takeaway.Events do
  @moduledoc "Events, which group speeches."
  import Ecto.Query
  alias Takeaway.Events.Event
  alias Takeaway.Organizers
  alias Takeaway.Organizers.Organizer
  alias Takeaway.Repo

  def list_events, do: Repo.all(from e in Event, order_by: [desc: e.inserted_at, desc: e.id])

  def get_event(id), do: Repo.get(Event, id)
  def get_event!(id), do: Repo.get!(Event, id)
  def get_event_by_join_code(code), do: Repo.get_by(Event, join_code: String.upcase(code))

  @doc """
  The event with `id`, only when `organizer` owns it.
  Returns `nil` for a missing or foreign event, so callers can't tell them apart.
  """
  def get_event_for_organizer(id, %Organizer{} = organizer) do
    with {int, ""} <- Integer.parse(to_string(id)),
         %Event{} = event <- get_event(int),
         true <- Organizers.owns_event?(organizer, event) do
      event
    else
      _ -> nil
    end
  end

  def get_event_for_organizer(_id, _organizer), do: nil

  def list_events_for_organizer(%Organizer{id: id}),
    do: Repo.all(from e in Event, where: e.organizer_id == ^id, order_by: [desc: e.id])

  @doc "Organizer page for the event's tickets."
  def tickets_path(%Event{id: id}), do: "/events/#{id}/tickets"

  def create_event(attrs, organizer \\ nil) do
    %Event{organizer_id: organizer && organizer.id} |> Event.changeset(attrs) |> Repo.insert()
  end

  def update_event(%Event{} = event, attrs), do: event |> Event.changeset(attrs) |> Repo.update()
end
