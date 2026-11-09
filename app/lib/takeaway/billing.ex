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
  Puts `event` on `plan` (or back on the default plan with `nil`).
  The only way to set `events.plan_id`: `Event.changeset/2` doesn't cast it,
  so form or request params can't change an event's plan.
  """
  def set_event_plan(%Takeaway.Events.Event{} = event, plan)
      when is_nil(plan) or is_struct(plan, Plan) do
    event
    |> Ecto.Changeset.change(plan_id: plan && plan.id)
    |> Ecto.Changeset.foreign_key_constraint(:plan_id)
    |> Repo.update()
  end

  @doc """
  The plan that applies to an event. An event without a plan (or a missing
  event) gets the default plan: the stored `"free"` plan if one exists,
  otherwise a built-in plan that allows every feature, so installs that never
  configured billing keep working.
  """
  def plan_for_event(%{plan_id: plan_id}) when not is_nil(plan_id),
    do: Repo.get(Plan, plan_id) || default_plan()

  def plan_for_event(_), do: default_plan()

  @doc "The plan that applies to a speech, via its event."
  def plan_for_speech(%{event_id: event_id}) when not is_nil(event_id),
    do: plan_for_event(Repo.get(Takeaway.Events.Event, event_id))

  def plan_for_speech(_), do: default_plan()

  @doc "Whether the plan behind `speech` allows `feature`."
  def speech_feature_allowed?(speech, feature),
    do: feature_allowed?(plan_for_speech(speech), feature)

  @doc "The stored `\"free\"` plan, or a permissive built-in one when none is stored."
  def default_plan do
    get_plan_by_key("free") || %Plan{key: "free", name: "Free", features: ["*"]}
  end

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
