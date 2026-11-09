defmodule TakeawayWeb.OrganizerHTML do
  @moduledoc "Pages rendered by OrganizerController."
  use TakeawayWeb, :html

  def log_in(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-sm px-4 py-6 space-y-4">
        <.header>Organizer log in</.header>
        <.form for={@form} id="login-form" action={~p"/organizers/log_in"} class="space-y-2">
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <button type="submit" class="btn btn-primary w-full">Log in</button>
        </.form>
        <p class="text-sm">
          No account? <a class="link" href={~p"/organizers/register"}>Register as an organizer</a>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def register(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-sm px-4 py-6 space-y-4">
        <.header>Register as an organizer</.header>
        <.form for={@form} id="register-form" action={~p"/organizers/register"} class="space-y-2">
          <.input field={@form[:name]} type="text" label="Name" autocomplete="name" />
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password (at least 8 characters)"
            autocomplete="new-password"
            required
          />
          <button type="submit" class="btn btn-primary w-full">Create account</button>
        </.form>
        <p class="text-sm">
          Already registered? <a class="link" href={~p"/organizers/log_in"}>Log in</a>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def dashboard(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl px-4 py-6 space-y-6">
        <.header>
          Your events
          <:subtitle>Signed in as {@current_organizer.email}</:subtitle>
          <:actions>
            <.link id="new-speech" class="btn btn-primary" href={~p"/speeches/new"}>
              New speech
            </.link>
            <.link id="log-out" class="btn" href={~p"/organizers/log_out"} method="delete">
              Log out
            </.link>
          </:actions>
        </.header>

        <p :if={@events == []} id="no-events" class="text-sm">
          No events yet. Create a speech and your event is set up for you.
        </p>

        <ul id="events" class="space-y-2">
          <li :for={event <- @events} id={"event-#{event.id}"} class="card bg-base-200 p-4">
            <span class="font-semibold">{event.name}</span>
            <a class="link tickets-link" href={Takeaway.Events.tickets_path(event)}>
              Manage tickets
            </a>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
