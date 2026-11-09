defmodule Takeaway.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :name, :string
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :join_code, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    has_many :speeches, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :description, :tags, :join_code, :started_at, :ended_at])
    |> validate_required([:name])
    |> Takeaway.JoinCode.put_join_code()
    |> unique_constraint(:join_code)
  end
end
