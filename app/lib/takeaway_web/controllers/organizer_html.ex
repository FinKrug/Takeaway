defmodule TakeawayWeb.OrganizerHTML do
  @moduledoc "Pages rendered by OrganizerController."
  use TakeawayWeb, :html

  import TakeawayWeb.SpeechList

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
      <.role_eyebrow icon="hero-building-office-2-mini" role="Organizer" />
      <.header class="-mt-4">
        Your conferences
        <:subtitle>
          Signed in as {@current_organizer.email}. Every conference you run and the speeches in
          it.
        </:subtitle>
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

      <.status_summary :if={@speeches != []} counts={@counts} />

      <.empty_state
        :if={@groups == []}
        id="no-events"
        icon="hero-calendar-days"
        title="No conferences or speeches yet"
      >
        Create a speech to get started. Choose "New conference…" to group several talks under
        one event.
      </.empty_state>

      <div id="events">
        <.conference_groups groups={@groups} empty_group="No speeches in this conference yet.">
          <:group_actions :let={event}>
            <.button
              href={Takeaway.Events.tickets_path(event)}
              variant="secondary"
              size="sm"
              class="tickets-link"
            >
              <.icon name="hero-ticket-mini" class="size-4" /> Manage tickets
            </.button>
          </:group_actions>
          <:meta :let={speech}>
            <span class="speaker-name">
              <.icon name="hero-microphone-mini" class="size-3.5" />
              {if speech.speaker,
                do: speech.speaker.name || speech.speaker.email,
                else: "No speaker yet"}
            </span>
          </:meta>
          <:actions :let={speech}>
            <.button
              href={~p"/speeches/#{speech.join_code}"}
              variant="secondary"
              size="sm"
              class="manage-link"
            >
              Manage
            </.button>
            <.button
              href={~p"/speeches/#{speech.id}/speak"}
              variant="ghost"
              size="sm"
              class="speak-link"
            >
              Speaker page
            </.button>
          </:actions>
        </.conference_groups>
      </div>
    </Layouts.app>
    """
  end
end
