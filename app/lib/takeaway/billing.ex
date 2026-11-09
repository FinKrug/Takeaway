defmodule Takeaway.Billing do
  @moduledoc """
  Plans and feature gating.

      Billing.feature_allowed?(plan, :summaries)
  """
  alias Takeaway.Billing.Plan
  alias Takeaway.Repo

  def create_plan(attrs) do
    %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
  end

  def get_plan_by_key(key), do: Repo.get_by(Plan, key: key)

  @doc """
  Returns true when `plan` allows `feature` (atom or string).
  A nil plan allows nothing. A plan with the `"*"` feature allows everything.
  """
  @spec feature_allowed?(%Plan{} | nil, atom() | String.t()) :: boolean()
  def feature_allowed?(nil, _feature), do: false

  def feature_allowed?(%Plan{features: features}, feature) do
    "*" in features or to_string(feature) in features
  end
end
