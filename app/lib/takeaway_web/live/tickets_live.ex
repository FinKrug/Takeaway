defmodule TakeawayWeb.TicketsLive do
  @moduledoc "Organizer page: generate tickets in bulk or import them from emails / CSV."
  use TakeawayWeb, :live_view

  alias Takeaway.{Events, Tickets}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {int, ""} -> mount_event(Events.get_event(int), socket)
      _ -> mount_event(nil, socket)
    end
  end

  defp mount_event(nil, socket) do
    {:ok, socket |> put_flash(:error, "Event not found") |> push_navigate(to: ~p"/")}
  end

  defp mount_event(event, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tickets")
     |> assign(:event, event)
     |> assign(:result, nil)
     |> assign(:generate_form, to_form(%{"count" => "10"}, as: :generate))
     |> assign(:import_form, to_form(%{"csv" => ""}, as: :import))
     |> load_tickets()}
  end

  @impl true
  def handle_event("generate", %{"generate" => %{"count" => count}}, socket) do
    with {n, ""} <- Integer.parse(count),
         {:ok, tickets} <- Tickets.generate_tickets(socket.assigns.event, n) do
      {:noreply,
       socket |> assign(:result, "Generated #{length(tickets)} tickets") |> load_tickets()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a number from 1 to 500")}
    end
  end

  def handle_event("import", %{"import" => %{"csv" => csv}}, socket) do
    r = Tickets.import_tickets(socket.assigns.event, csv)

    msg =
      "Imported #{length(r.created)}, skipped #{length(r.skipped)} existing, " <>
        "#{length(r.invalid)} invalid"

    {:noreply, socket |> assign(:result, msg) |> load_tickets()}
  end

  defp load_tickets(socket),
    do: assign(socket, :tickets, Tickets.list_tickets(socket.assigns.event.id))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl px-4 py-6 space-y-6">
        <.header>Tickets for {@event.name}</.header>
        <p :if={@result} id="result" class="text-sm">{@result}</p>

        <.form for={@generate_form} id="generate-form" phx-submit="generate" class="space-y-2">
          <.input
            field={@generate_form[:count]}
            type="number"
            label="Generate tickets"
            min="1"
            max="500"
          />
          <button type="submit" class="btn btn-primary">Generate</button>
        </.form>

        <.form for={@import_form} id="import-form" phx-submit="import" class="space-y-2">
          <.input
            field={@import_form[:csv]}
            type="textarea"
            label="Import attendees (one per line: email or email,name)"
          />
          <button type="submit" class="btn btn-primary">Import</button>
        </.form>

        <div>
          <h2 class="font-semibold">{length(@tickets)} tickets</h2>
          <ul id="tickets" class="font-mono text-sm">
            <li :for={t <- @tickets}>{t.code}</li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
