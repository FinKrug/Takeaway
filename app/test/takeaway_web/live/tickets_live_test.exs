defmodule TakeawayWeb.TicketsLiveTest do
  use TakeawayWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Takeaway.{Events, Tickets}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    %{event: event}
  end

  test "generates tickets", %{conn: conn, event: e} do
    {:ok, lv, _} = live(conn, ~p"/events/#{e.id}/tickets")
    html = lv |> form("#generate-form", generate: %{count: "3"}) |> render_submit()
    assert html =~ "Generated 3 tickets"
    assert length(Tickets.list_tickets(e.id)) == 3
  end

  test "imports attendees", %{conn: conn, event: e} do
    {:ok, lv, _} = live(conn, ~p"/events/#{e.id}/tickets")
    html = lv |> form("#import-form", import: %{csv: "a@x.com\nbad"}) |> render_submit()
    assert html =~ "Imported 1, skipped 0 existing, 1 invalid"
  end
end
