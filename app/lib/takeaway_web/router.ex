defmodule TakeawayWeb.Router do
  use TakeawayWeb, :router

  import TakeawayWeb.OrganizerAuth

  import TakeawayWeb.UserAuth,
    only: [
      fetch_current_user: 2,
      require_user: 2,
      require_speaker: 2,
      require_organizer_or_speaker: 2,
      redirect_if_user: 2
    ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TakeawayWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_organizer
    plug :fetch_current_user
  end

  pipeline :attendee do
    plug TakeawayWeb.AttendeeSession
  end

  pipeline :guest_only do
    plug :redirect_if_organizer
  end

  pipeline :user_guest_only do
    plug :redirect_if_user
  end

  pipeline :user_only do
    plug :require_user
  end

  pipeline :speaker_only do
    plug :require_speaker
  end

  pipeline :organizer_or_speaker do
    plug :require_organizer_or_speaker
  end

  pipeline :organizer_only do
    plug :require_organizer
  end

  # Kubernetes probes: no session, no CSRF.
  scope "/", TakeawayWeb do
    get "/healthz", HealthController, :show
    get "/readyz", HealthController, :show
  end

  scope "/", TakeawayWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/join", PageController, :join
    get "/artifacts/:id", ArtifactController, :show
  end

  # Attendee page: the plug gives each attendee an anonymous identity in the session.
  scope "/", TakeawayWeb do
    pipe_through [:browser, :attendee]

    live_session :attendee, on_mount: {TakeawayWeb.UserAuth, :mount_current_user} do
      live "/join/:code", SpeechLive.Join
    end
  end

  # Speaker and attendee accounts: sign-up, login, logout.
  scope "/", TakeawayWeb do
    pipe_through [:browser, :user_guest_only]

    get "/users/log_in", UserController, :new_session
    post "/users/log_in", UserController, :create_session
    get "/users/register", UserController, :new_registration
    post "/users/register", UserController, :create_registration
    get "/users/invite/:token", UserController, :new_invite
    post "/users/invite/:token", UserController, :claim_invite
  end

  scope "/", TakeawayWeb do
    pipe_through :browser

    delete "/users/log_out", UserController, :delete_session
  end

  scope "/", TakeawayWeb do
    pipe_through [:browser, :speaker_only]

    get "/speaker", UserController, :speaker_dashboard
  end

  scope "/", TakeawayWeb do
    pipe_through [:browser, :user_only]

    get "/account", UserController, :account
  end

  # Speaker page: the event's organizer or the speech's own speaker. SpeakerLive checks
  # which speech, on mount and on every event.
  scope "/", TakeawayWeb do
    pipe_through [:browser, :organizer_or_speaker]

    live_session :speaker_access,
      on_mount: {TakeawayWeb.UserAuth, :require_organizer_or_speaker} do
      live "/speeches/:id/speak", SpeakerLive
    end
  end

  # Organizer login, sign-up and logout.
  scope "/", TakeawayWeb do
    pipe_through [:browser, :guest_only]

    get "/organizers/log_in", OrganizerController, :new_session
    post "/organizers/log_in", OrganizerController, :create_session
    get "/organizers/register", OrganizerController, :new_registration
    post "/organizers/register", OrganizerController, :create_registration
  end

  scope "/", TakeawayWeb do
    pipe_through :browser

    delete "/organizers/log_out", OrganizerController, :delete_session
  end

  # Organizer pages: only for a logged-in organizer, and each page checks ownership.
  scope "/", TakeawayWeb do
    pipe_through [:browser, :organizer_only]

    get "/organizers", OrganizerController, :dashboard

    live_session :organizer, on_mount: {TakeawayWeb.OrganizerAuth, :require_organizer} do
      live "/events/:id/tickets", TicketsLive
      live "/speeches/new", SpeechLive.New
      live "/speeches/:code", SpeechLive.Show
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:takeaway, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TakeawayWeb.Telemetry
    end
  end
end
