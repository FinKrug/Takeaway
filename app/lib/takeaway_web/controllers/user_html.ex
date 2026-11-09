defmodule TakeawayWeb.UserHTML do
  @moduledoc "Pages rendered by UserController."
  use TakeawayWeb, :html

  def log_in(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-sm space-y-6">
        <.header>
          Log in
          <:subtitle>For speakers and attendees with an account.</:subtitle>
        </.header>
        <.card>
          <.form for={@form} id="login-form" action={~p"/users/log_in"} class="space-y-4">
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
            href={~p"/users/register"}
          >
            Sign up
          </.link>
          &middot;
          <.link
            class="font-semibold text-brand-strong underline-offset-4 hover:underline"
            href={~p"/organizers/log_in"}
          >
            Organizer log in
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
          Sign up
          <:subtitle>Speakers present talks; attendees keep their notes and questions.</:subtitle>
        </.header>
        <.card>
          <.form for={@form} id="register-form" action={~p"/users/register"} class="space-y-4">
            <.input
              field={@form[:role]}
              type="select"
              label="I am a"
              options={[Attendee: "attendee", Speaker: "speaker"]}
            />
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
            href={~p"/users/log_in"}
          >
            Log in
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def invite(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-sm space-y-6">
        <.header>
          Accept your invite
          <:subtitle>Set a name and password to open your speaker pages.</:subtitle>
        </.header>
        <.card>
          <.form
            for={@form}
            id="invite-form"
            action={~p"/users/invite/#{@token}"}
            class="space-y-4"
          >
            <.input field={@form[:name]} type="text" label="Name" autocomplete="name" required />
            <.input
              name="invited_email"
              id="invited-email"
              type="email"
              label="Email"
              value={@email}
              readonly
            />
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
      </div>
    </Layouts.app>
    """
  end

  def invalid_invite(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-sm space-y-6">
        <.header>
          This invite link is not valid
          <:subtitle>
            It may have been used or replaced. Ask the organizer for a new link, or log in if
            you already have an account.
          </:subtitle>
        </.header>
        <.button href={~p"/users/log_in"} size="lg" class="w-full">Log in</.button>
      </div>
    </Layouts.app>
    """
  end

  def speaker_dashboard(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Your speeches
        <:subtitle>Signed in as {@current_user.name} ({@current_user.email})</:subtitle>
      </.header>

      <.empty_state
        :if={@speeches == []}
        id="no-speeches"
        icon="hero-presentation-chart-bar"
        title="No speeches yet"
      >
        No speeches yet. An organizer adds you to a speech with your email address.
      </.empty_state>

      <ul id="speeches" class="space-y-3">
        <li :for={speech <- @speeches} id={"speech-#{speech.id}"}>
          <.card class="flex items-center justify-between gap-3">
            <span class="min-w-0 truncate font-semibold">{speech.title}</span>
            <.button
              href={~p"/speeches/#{speech.id}/speak"}
              variant="secondary"
              size="sm"
              class="speak-link shrink-0"
            >
              Open speaker page
            </.button>
          </.card>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  def account(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Your account
        <:subtitle>{@current_user.name || "Attendee"} ({@current_user.email})</:subtitle>
      </.header>

      <.empty_state
        :if={@speeches == []}
        id="no-speeches"
        icon="hero-chat-bubble-left-right"
        title="Nothing yet"
      >
        Join a talk with its code. Questions you ask and notes you take show up here.
      </.empty_state>

      <ul id="speeches" class="space-y-3">
        <li :for={speech <- @speeches} id={"speech-#{speech.id}"}>
          <.card class="flex items-center justify-between gap-3">
            <span class="min-w-0 truncate font-semibold">{speech.title}</span>
            <.button
              href={~p"/join/#{speech.join_code}"}
              variant="secondary"
              size="sm"
              class="join-link shrink-0"
            >
              Open
            </.button>
          </.card>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
