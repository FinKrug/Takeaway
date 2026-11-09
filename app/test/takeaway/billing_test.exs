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
end
