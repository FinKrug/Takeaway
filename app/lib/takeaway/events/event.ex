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

    # Legacy secret from before organizer accounts; no longer unlocks anything. Generated, never cast.
    field :admin_token, :string, redact: true

    # The owner; set only through `Takeaway.Organizers.claim_event/2` or `Events.create_event/2`.
    belongs_to :organizer, Takeaway.Organizers.Organizer

    # Set only through `Takeaway.Billing.set_event_plan/2`, never cast.
    belongs_to :plan, Takeaway.Billing.Plan
    has_many :speeches, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :description, :tags, :join_code, :started_at, :ended_at])
    |> validate_required([:name])
    |> Takeaway.JoinCode.put_join_code()
    |> put_admin_token()
    |> unique_constraint(:join_code)
    |> unique_constraint(:admin_token)
  end

  defp put_admin_token(changeset) do
    if get_field(changeset, :admin_token) do
      changeset
    else
      put_change(changeset, :admin_token, generate_admin_token())
    end
  end

  @doc "A random, URL-safe 32-character token."
  def generate_admin_token,
    do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
