defmodule TakeawayWeb.Router do
  use TakeawayWeb, :router

  import TakeawayWeb.OrganizerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TakeawayWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_organizer
  end

  pipeline :guest_only do
    plug :redirect_if_organizer
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

    live "/join/:code", SpeechLive.Join
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
      live "/speeches/:id/speak", SpeakerLive
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
