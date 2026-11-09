defmodule TakeawayWeb.TicketsLiveTest do
  use TakeawayWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Takeaway.{Events, Tickets}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    %{event: event}
  end

  test "generates tickets", %{conn: conn, event: e} do
    {:ok, lv, _} = live(conn, Events.tickets_path(e))
    html = lv |> form("#generate-form", generate: %{count: "3"}) |> render_submit()
    assert html =~ "Generated 3 tickets"
    assert html =~ "3 tickets"
    assert length(Tickets.list_tickets(e.id)) == 3

    for t <- Tickets.list_tickets(e.id), do: assert(html =~ t.code)
  end

  test "imports attendees", %{conn: conn, event: e} do
    {:ok, lv, _} = live(conn, Events.tickets_path(e))
    html = lv |> form("#import-form", import: %{csv: "a@x.com\nbad"}) |> render_submit()
    assert html =~ "Imported 1, skipped 0 existing, 1 invalid"
    assert html =~ "1 tickets"
  end

  test "lists existing tickets on mount", %{conn: conn, event: e} do
    {:ok, [t]} = Tickets.generate_tickets(e, 1)
    {:ok, _lv, html} = live(conn, Events.tickets_path(e))
    assert html =~ t.code
  end

  describe "without the admin token" do
    test "missing token redirects and reveals nothing", %{conn: conn, event: e} do
      {:ok, _} = Tickets.generate_tickets(e, 1)

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Event not found"}}}} =
               live(conn, ~p"/events/#{e.id}/tickets")
    end

    test "wrong token redirects", %{conn: conn, event: e} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/events/#{e.id}/tickets?token=nope")
    end

    test "another event's token doesn't work", %{conn: conn, event: e} do
      {:ok, other} = Events.create_event(%{name: "Other"})

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/events/#{e.id}/tickets?token=#{other.admin_token}")
    end
  end
end
