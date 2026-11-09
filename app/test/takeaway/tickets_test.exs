defmodule Takeaway.TicketsTest do
  use Takeaway.DataCase, async: false

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
end
