defmodule Takeaway.TicketsTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.{Events, Tickets}

  setup do
    {:ok, e1} = Events.create_event(%{name: "One"})
    {:ok, e2} = Events.create_event(%{name: "Two"})
    %{e1: e1, e2: e2}
  end

  test "generates a code", %{e1: e} do
    assert {:ok, t} = Tickets.create_ticket(%{event_id: e.id})
    assert String.length(t.code) == 8
    assert Tickets.get_ticket_by_code(e.id, String.downcase(t.code)).id == t.id
  end

  test "code is unique per event", %{e1: e1, e2: e2} do
    assert {:ok, _} = Tickets.create_ticket(%{event_id: e1.id, code: "abc12345"})
    assert {:error, cs} = Tickets.create_ticket(%{event_id: e1.id, code: "ABC12345"})
    assert "has already been taken" in errors_on(cs).code
    assert {:ok, _} = Tickets.create_ticket(%{event_id: e2.id, code: "ABC12345"})
  end

  test "event is required" do
    assert {:error, cs} = Tickets.create_ticket(%{})
    assert "can't be blank" in errors_on(cs).event_id
  end

  test "retries with a new code on collision, inside a transaction", %{e1: e} do
    {:ok, _} = Tickets.create_ticket(%{event_id: e.id, code: "TAKEN123"})
    codes = Agent.start_link(fn -> ["TAKEN123", "TAKEN123", "FRESH123"] end) |> elem(1)
    gen = fn -> Agent.get_and_update(codes, fn [c | rest] -> {c, rest} end) end

    assert {:ok, {:ok, t}} =
             Takeaway.Repo.transaction(fn ->
               Tickets.create_ticket(%{event_id: e.id}, generate: gen)
             end)

    assert t.code == "FRESH123"
  end

  test "blank code is generated and still retried", %{e1: e} do
    {:ok, _} = Tickets.create_ticket(%{event_id: e.id, code: "TAKEN123"})
    codes = Agent.start_link(fn -> ["TAKEN123", "FRESH123"] end) |> elem(1)
    gen = fn -> Agent.get_and_update(codes, fn [c | rest] -> {c, rest} end) end

    assert {:ok, t} = Tickets.create_ticket(%{"event_id" => e.id, "code" => ""}, generate: gen)
    assert t.code == "FRESH123"
  end
end
