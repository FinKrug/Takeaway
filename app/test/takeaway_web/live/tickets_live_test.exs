defmodule TakeawayWeb.TicketsLiveTest do
  use TakeawayWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Takeaway.{Events, Organizers, Tickets}

  setup %{conn: conn} do
    organizer = organizer_fixture()
    {:ok, event} = Events.create_event(%{name: "Conf"}, organizer)
    %{event: event, organizer: organizer, conn: log_in_organizer(conn, organizer)}
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

  test "the dashboard links the organizer to their tickets page", %{conn: conn, event: e} do
    html = conn |> get(~p"/organizers") |> html_response(200)
    assert html =~ "Conf"
    assert html =~ ~s(href="/events/#{e.id}/tickets")
  end

  describe "access control" do
    test "logged-out visitors go to the login page", %{event: e} do
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/events/#{e.id}/tickets")
      assert redirected_to(conn) == ~p"/organizers/log_in"
    end

    test "the old admin-token link no longer works", %{event: e} do
      conn =
        get(Phoenix.ConnTest.build_conn(), ~p"/events/#{e.id}/tickets?token=#{e.admin_token}")

      assert redirected_to(conn) == ~p"/organizers/log_in"
    end

    test "another organizer can't open the page", %{event: e} do
      conn = log_in_organizer(Phoenix.ConnTest.build_conn(), organizer_fixture())

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Event not found"}}}} =
               live(conn, ~p"/events/#{e.id}/tickets")
    end

    test "unowned events are closed to every organizer", %{conn: conn} do
      {:ok, orphan} = Events.create_event(%{name: "Old"})

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/events/#{orphan.id}/tickets")

      {:ok, _} = Organizers.claim_event(orphan, organizer_fixture())
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/events/#{orphan.id}/tickets")
    end
  end
end
