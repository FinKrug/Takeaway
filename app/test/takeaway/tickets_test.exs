defmodule Takeaway.TicketsTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.{Accounts, Events, Tickets}
  alias Takeaway.Tickets.Ticket

  setup do
    {:ok, e1} = Events.create_event(%{name: "One"})
    {:ok, e2} = Events.create_event(%{name: "Two"})
    %{e1: e1, e2: e2}
  end

  test "generates a code", %{e1: e} do
    assert {:ok, t} = Tickets.create_ticket(e)
    assert String.length(t.code) == 8
    assert t.event_id == e.id
    assert t.user_id == nil
    assert Tickets.get_ticket_by_code(e.id, String.downcase(t.code)).id == t.id
  end

  test "sets the owner from the user struct", %{e1: e} do
    {:ok, u} = Accounts.create_anonymous_attendee()
    assert {:ok, t} = Tickets.create_ticket(e, u)
    assert t.user_id == u.id
  end

  test "ignores event_id and user_id in attrs", %{e1: e1, e2: e2} do
    {:ok, owner} = Accounts.create_anonymous_attendee()
    {:ok, other} = Accounts.create_anonymous_attendee()

    assert {:ok, t} =
             Tickets.create_ticket(e1, owner, %{
               "event_id" => e2.id,
               "user_id" => other.id,
               "code" => "OWNED123"
             })

    assert t.event_id == e1.id
    assert t.user_id == owner.id
  end

  test "changeset does not cast ownership ids", %{e1: e} do
    cs = Ticket.changeset(%Ticket{}, %{event_id: e.id, user_id: 1, code: "ABC12345"})
    refute Map.has_key?(cs.changes, :event_id)
    refute Map.has_key?(cs.changes, :user_id)
    assert "can't be blank" in errors_on(cs).event_id
  end

  test "code is unique per event", %{e1: e1, e2: e2} do
    assert {:ok, _} = Tickets.create_ticket(e1, nil, %{code: "abc12345"})
    assert {:error, cs} = Tickets.create_ticket(e1, nil, %{code: "ABC12345"})
    assert "has already been taken" in errors_on(cs).code
    assert {:ok, _} = Tickets.create_ticket(e2, nil, %{code: "ABC12345"})
  end

  test "retries with a new code on collision, inside a transaction", %{e1: e} do
    {:ok, _} = Tickets.create_ticket(e, nil, %{code: "TAKEN123"})
    codes = Agent.start_link(fn -> ["TAKEN123", "TAKEN123", "FRESH123"] end) |> elem(1)
    gen = fn -> Agent.get_and_update(codes, fn [c | rest] -> {c, rest} end) end

    assert {:ok, {:ok, t}} =
             Takeaway.Repo.transaction(fn ->
               Tickets.create_ticket(e, nil, %{}, generate: gen)
             end)

    assert t.code == "FRESH123"
  end

  test "blank code is generated and still retried", %{e1: e} do
    {:ok, _} = Tickets.create_ticket(e, nil, %{code: "TAKEN123"})
    codes = Agent.start_link(fn -> ["TAKEN123", "FRESH123"] end) |> elem(1)
    gen = fn -> Agent.get_and_update(codes, fn [c | rest] -> {c, rest} end) end

    assert {:ok, t} = Tickets.create_ticket(e, nil, %{"code" => ""}, generate: gen)
    assert t.code == "FRESH123"
  end

  describe "bulk" do
    test "generate_tickets creates unowned tickets", %{e1: e} do
      assert {:ok, ts} = Tickets.generate_tickets(e, 5)
      assert length(Enum.uniq_by(ts, & &1.code)) == 5
      assert length(Tickets.list_tickets(e.id)) == 5
    end

    test "generate_tickets rejects bad counts", %{e1: e} do
      assert {:error, :invalid_count} = Tickets.generate_tickets(e, 0)
      assert {:error, :invalid_count} = Tickets.generate_tickets(e, 501)
    end

    test "import_tickets creates attendees, skips duplicates, flags invalid", %{e1: e, e2: e2} do
      text = "email,name\nA@x.com, Ann\nb@x.com\nnot-an-email\n\na@x.com\n"
      r = Tickets.import_tickets(e, text)
      assert length(r.created) == 2
      assert r.skipped == ["a@x.com"]
      assert r.invalid == ["not-an-email"]
      assert Enum.all?(r.created, & &1.user_id)

      r2 = Tickets.import_tickets(e2, "a@x.com")
      assert [t] = r2.created
      assert t.user_id == hd(r.created).user_id
    end
  end
end
