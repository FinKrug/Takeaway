defmodule TakeawayWeb.OrganizerHTML do
  @moduledoc "Pages rendered by OrganizerController."
  use TakeawayWeb, :html

  def log_in(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-sm space-y-6">
        <.header>
          Organizer log in
          <:subtitle>Manage your events, speeches and tickets.</:subtitle>
        </.header>
        <.card>
          <.form for={@form} id="login-form" action={~p"/organizers/log_in"} class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              required
            />
            <.button type="submit" size="lg" class="w-full">Log in</.button>
          </.form>
        </.card>
        <p class="text-center text-sm text-muted">
          No account?
          <.link
            class="font-semibold text-brand-strong underline-offset-4 hover:underline"
            href={~p"/organizers/register"}
          >
            Register as an organizer
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def register(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-sm space-y-6">
        <.header>
          Register as an organizer
          <:subtitle>Create speeches, share join codes and hand out tickets.</:subtitle>
        </.header>
        <.card>
          <.form for={@form} id="register-form" action={~p"/organizers/register"} class="space-y-4">
            <.input field={@form[:name]} type="text" label="Name" autocomplete="name" />
            <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              hint="At least 8 characters."
              autocomplete="new-password"
              required
            />
            <.button type="submit" size="lg" class="w-full">Create account</.button>
          </.form>
        </.card>
        <p class="text-center text-sm text-muted">
          Already registered?
          <.link
            class="font-semibold text-brand-strong underline-offset-4 hover:underline"
            href={~p"/organizers/log_in"}
          >
            Log in
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def dashboard(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Your events
        <:subtitle>Signed in as {@current_organizer.email}</:subtitle>
        <:actions>
          <.button id="new-speech" href={~p"/speeches/new"} size="sm">
            <.icon name="hero-plus-mini" class="size-4" /> New speech
          </.button>
          <.button
            id="log-out"
            href={~p"/organizers/log_out"}
            method="delete"
            variant="secondary"
            size="sm"
          >
            Log out
          </.button>
        </:actions>
      </.header>

      <.empty_state
        :if={@events == []}
        id="no-events"
        icon="hero-calendar-days"
        title="No events yet"
      >
        No events yet. Create a speech and your event is set up for you.
      </.empty_state>

      <ul id="events" class="space-y-3">
        <li :for={event <- @events} id={"event-#{event.id}"}>
          <.card class="flex items-center justify-between gap-3">
            <span class="min-w-0 truncate font-semibold">{event.name}</span>
            <.button
              href={Takeaway.Events.tickets_path(event)}
              variant="secondary"
              size="sm"
              class="tickets-link shrink-0"
            >
              <.icon name="hero-ticket-mini" class="size-4" /> Manage tickets
            </.button>
          </.card>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
