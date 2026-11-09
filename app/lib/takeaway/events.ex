defmodule Takeaway.Events do
  @moduledoc "Events, which group speeches."
  import Ecto.Query
  alias Takeaway.Events.Event
  alias Takeaway.Repo

  def list_events, do: Repo.all(from e in Event, order_by: [desc: e.inserted_at, desc: e.id])

  def get_event(id), do: Repo.get(Event, id)
  def get_event!(id), do: Repo.get!(Event, id)
  def get_event_by_join_code(code), do: Repo.get_by(Event, join_code: String.upcase(code))

  def create_event(attrs), do: %Event{} |> Event.changeset(attrs) |> Repo.insert()

  def update_event(%Event{} = event, attrs), do: event |> Event.changeset(attrs) |> Repo.update()
end
