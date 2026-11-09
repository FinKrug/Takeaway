defmodule TakeawayWeb.Router do
  use TakeawayWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TakeawayWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Kubernetes probes: no session, no CSRF.
  scope "/", TakeawayWeb do
    get "/healthz", HealthController, :show
    get "/readyz", HealthController, :show
  end

  scope "/", TakeawayWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/artifacts/:id", ArtifactController, :show

    live "/speeches/new", SpeechLive.New
    live "/speeches/:code", SpeechLive.Show
    live "/join/:code", SpeechLive.Join
    live "/speeches/:id/speak", SpeakerLive
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
