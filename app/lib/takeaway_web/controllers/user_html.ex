defmodule TakeawayWeb.UserHTML do
  @moduledoc "Pages rendered by UserController."
  use TakeawayWeb, :html

  import TakeawayWeb.SpeechList

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
      <.role_eyebrow icon="hero-microphone-mini" role="Speaker" />
      <.header class="-mt-4">
        Your speeches
        <:subtitle>
          Signed in as {@current_user.name} ({@current_user.email}). Talks you give, by
          conference.
        </:subtitle>
        <:actions>
          <.log_out_button />
        </:actions>
      </.header>

      <.card :for={speech <- @live} id={"live-now-#{speech.id}"} tone="brand" class="space-y-3">
        <p class="flex items-center gap-2 font-semibold text-success">
          <span class="size-2 rounded-full bg-current motion-safe:animate-pulse" aria-hidden="true" />
          You're live: {speech.title}
        </p>
        <.button href={~p"/speeches/#{speech.id}/speak"} class="w-full sm:w-auto">
          Open speaker page
        </.button>
      </.card>

      <.status_summary
        :if={@speeches != []}
        counts={@counts}
        labels={%{live: "Live now", upcoming: "To give", ended: "Given"}}
      />

      <.empty_state
        :if={@speeches == []}
        id="no-speeches"
        icon="hero-presentation-chart-bar"
        title="No speeches yet"
      >
        An organizer adds you to a speech with your email address ({@current_user.email}).
        Once they do, it shows up here, under its conference.
      </.empty_state>

      <div id="speeches">
        <.conference_groups groups={@groups}>
          <:actions :let={speech}>
            <.button
              href={~p"/speeches/#{speech.id}/speak"}
              variant={
                if Takeaway.Speeches.Speech.status(speech) == :live, do: "primary", else: "secondary"
              }
              size="sm"
              class="speak-link"
            >
              Open speaker page
            </.button>
          </:actions>
        </.conference_groups>
      </div>
    </Layouts.app>
    """
  end

  def account(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.role_eyebrow icon="hero-user-mini" role="Attendee" />
      <.header class="-mt-4">
        Your talks
        <:subtitle>
          Signed in as {@current_user.name || "Attendee"} ({@current_user.email}). Talks where
          you asked a question or took notes, by conference.
        </:subtitle>
        <:actions>
          <.button href={~p"/#join"} size="sm" id="join-a-talk">
            <.icon name="hero-arrow-right-end-on-rectangle-mini" class="size-4" /> Join a talk
          </.button>
          <.log_out_button />
        </:actions>
      </.header>

      <.status_summary :if={@speeches != []} counts={@counts} />

      <.empty_state
        :if={@speeches == []}
        id="no-speeches"
        icon="hero-chat-bubble-left-right"
        title="Nothing yet"
      >
        Join a talk with its code. Questions you ask and notes you take show up here.
      </.empty_state>

      <div id="speeches">
        <.conference_groups groups={@groups}>
          <:meta :let={speech}>
            <span class="activity">{activity_text(@activity[speech.id])}</span>
          </:meta>
          <:actions :let={speech}>
            <.button
              href={~p"/join/#{speech.join_code}"}
              variant="secondary"
              size="sm"
              class="join-link"
            >
              {if Takeaway.Speeches.Speech.status(speech) == :ended, do: "Review", else: "Open"}
            </.button>
          </:actions>
        </.conference_groups>
      </div>
    </Layouts.app>
    """
  end

  defp log_out_button(assigns) do
    ~H"""
    <.button id="log-out" href={~p"/users/log_out"} method="delete" variant="secondary" size="sm">
      Log out
    </.button>
    """
  end

  @doc false
  def activity_text(nil), do: ""

  def activity_text(%{questions: q, note?: note?}) do
    [
      q > 0 && "#{q} #{if q == 1, do: "question", else: "questions"}",
      note? && "notes"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
