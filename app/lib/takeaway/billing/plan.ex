defmodule Takeaway.Billing.Plan do
  @moduledoc """
  A subscription plan. `features` lists the feature keys the plan allows
  (`"*"` allows everything); `limits` is a free-form map of numeric limits,
  e.g. `%{"max_speeches" => 5}`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :key, :string
    field :name, :string
    field :features, {:array, :string}, default: []
    field :limits, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:key, :name, :features, :limits])
    |> validate_required([:key, :name])
    |> unique_constraint(:key)
  end
end
