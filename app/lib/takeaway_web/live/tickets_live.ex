defmodule TakeawayWeb.TicketsLive do
  @moduledoc """
  Organizer page: generate tickets in bulk or import them from emails / CSV.

  Reachable only by the organizer who owns the event: `/events/:id/tickets`
  (see `Takeaway.Events.tickets_path/1`), linked from the organizer dashboard
  and from each speech page.
  """
  use TakeawayWeb, :live_view

  alias Takeaway.{Events, Tickets}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Events.get_event_for_organizer(id, socket.assigns.current_organizer) do
      nil ->
        {:ok, socket |> put_flash(:error, "Event not found") |> push_navigate(to: ~p"/")}

      event ->
        tickets = Tickets.list_tickets(event.id)

        {:ok,
         socket
         |> assign(:page_title, "Tickets")
         |> assign(:event, event)
         |> assign(:result, nil)
         |> assign(:ticket_count, length(tickets))
         |> assign(:generate_form, to_form(%{"count" => "10"}, as: :generate))
         |> assign(:import_form, to_form(%{"csv" => ""}, as: :import))
         |> stream(:tickets, tickets)}
    end
  end

  @impl true
  def handle_event("generate", %{"generate" => %{"count" => count}}, socket) do
    with {n, ""} <- Integer.parse(count),
         {:ok, tickets} <- Tickets.generate_tickets(socket.assigns.event, n) do
      {:noreply,
       socket
       |> assign(:result, "Generated #{length(tickets)} tickets")
       |> add_tickets(tickets)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a number from 1 to 500")}
    end
  end

  def handle_event("import", %{"import" => %{"csv" => csv}}, socket) do
    r = Tickets.import_tickets(socket.assigns.event, csv)

    msg =
      "Imported #{length(r.created)}, skipped #{length(r.skipped)} existing, " <>
        "#{length(r.invalid)} invalid"

    {:noreply, socket |> assign(:result, msg) |> add_tickets(r.created)}
  end

  defp add_tickets(socket, tickets) do
    socket
    |> update(:ticket_count, &(&1 + length(tickets)))
    |> stream(:tickets, tickets)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Tickets for {@event.name}</.header>

      <p
        :if={@result}
        id="result"
        class="rounded-xl bg-success-soft px-3.5 py-2.5 text-sm font-medium motion-safe:animate-pop"
      >
        {@result}
      </p>

      <div class="grid gap-4 sm:grid-cols-2">
        <.card>
          <.form for={@generate_form} id="generate-form" phx-submit="generate" class="space-y-3">
            <.input
              field={@generate_form[:count]}
              type="number"
              label="Generate tickets"
              min="1"
              max="500"
              inputmode="numeric"
            /> <.button type="submit" class="w-full">Generate</.button>
          </.form>
        </.card>

        <.card>
          <.form for={@import_form} id="import-form" phx-submit="import" class="space-y-3">
            <.input
              field={@import_form[:csv]}
              type="textarea"
              label="Import attendees"
              hint="One per line: email or email,name"
              rows="3"
            /> <.button type="submit" variant="secondary" class="w-full">Import</.button>
          </.form>
        </.card>
      </div>

      <.card>
        <h2 id="ticket-count" class="mb-3 font-display font-semibold tracking-tight">
          {@ticket_count} tickets
        </h2>

        <ul id="tickets" phx-update="stream" class="flex flex-wrap gap-2 font-mono text-sm">
          <li :for={{dom_id, t} <- @streams.tickets} id={dom_id}>
            <.badge tone="outline" class="font-mono text-xs tracking-wider">{t.code}</.badge>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end
end
