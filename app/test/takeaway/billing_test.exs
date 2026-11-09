defmodule Takeaway.BillingTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.Billing
  alias Takeaway.Billing.Plan

  test "create_plan persists features and limits" do
    {:ok, plan} =
      Billing.create_plan(%{
        key: "pro",
        name: "Pro",
        features: ["summaries"],
        limits: %{"max_speeches" => 5}
      })

    assert Billing.get_plan_by_key("pro").id == plan.id
    assert plan.limits == %{"max_speeches" => 5}
  end

  test "key and name are required, key is unique" do
    assert {:error, cs} = Billing.create_plan(%{})
    assert %{key: _, name: _} = errors_on(cs)

    {:ok, _} = Billing.create_plan(%{key: "free", name: "Free"})
    assert {:error, cs} = Billing.create_plan(%{key: "free", name: "Again"})
    assert %{key: ["has already been taken"]} = errors_on(cs)
  end

  describe "feature_allowed?/2" do
    test "checks listed features, atom or string" do
      plan = %Plan{features: ["summaries"]}
      assert Billing.feature_allowed?(plan, :summaries)
      assert Billing.feature_allowed?(plan, "summaries")
      refute Billing.feature_allowed?(plan, :export)
    end

    test "wildcard allows everything" do
      assert Billing.feature_allowed?(%Plan{features: ["*"]}, :anything)
    end

    test "nil plan allows nothing" do
      refute Billing.feature_allowed?(nil, :summaries)
    end
  end

  test "nil features or limits is a changeset error, not a crash" do
    assert {:error, cs} = Billing.create_plan(%{key: "x", name: "X", features: nil})
    assert "can't be blank" in errors_on(cs).features
    assert {:error, cs} = Billing.create_plan(%{key: "y", name: "Y", limits: nil})
    assert "can't be blank" in errors_on(cs).limits
  end

  describe "speech_feature_allowed?/2" do
    setup do
      {:ok, event} = Takeaway.Events.create_event(%{name: "Conf"})
      {:ok, speech} = Takeaway.Speeches.create_speech(%{title: "T", event_id: event.id})
      %{event: event, speech: speech}
    end

    test "defaults to a permissive plan when nothing is configured", %{speech: speech} do
      assert Billing.speech_feature_allowed?(speech, :summaries)
    end

    test "uses the stored free plan as the default", %{speech: speech} do
      {:ok, _} = Billing.create_plan(%{key: "free", name: "Free", features: []})
      refute Billing.speech_feature_allowed?(speech, :summaries)
    end

    test "uses the event's own plan", %{event: event, speech: speech} do
      {:ok, _} = Billing.create_plan(%{key: "free", name: "Free", features: []})
      {:ok, pro} = Billing.create_plan(%{key: "pro", name: "Pro", features: ["summaries"]})

      {:ok, _} =
        event |> Takeaway.Events.Event.changeset(%{plan_id: pro.id}) |> Takeaway.Repo.update()

      assert Billing.speech_feature_allowed?(speech, :summaries)
    end
  end
end
