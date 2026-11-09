defmodule Takeaway.Tickets.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tickets" do
    field :code, :string

    belongs_to :event, Takeaway.Events.Event
    belongs_to :user, Takeaway.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Casts only the user-supplied `:code`. Ownership (`event_id`, `user_id`) is never
  cast from attrs; set it on the struct before calling this (see `Takeaway.Tickets`).
  """
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:code])
    |> validate_required([:event_id])
    |> Takeaway.JoinCode.put_code(:code, 8)
    |> update_change(:code, &String.upcase/1)
    |> foreign_key_constraint(:event_id)
    |> unique_constraint(:code, name: :tickets_event_id_code_index)
  end
end
