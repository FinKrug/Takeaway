defmodule Takeaway.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OpenTelemetry spans for HTTP requests, Phoenix routes and LiveViews, and
    # Ecto queries. They're exported only when config/runtime.exs turns the
    # Dash0 exporter on; otherwise they're dropped.
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:takeaway, :repo], db_statement: :enabled)

    children = [
      TakeawayWeb.Telemetry,
      Takeaway.Repo,
      {DNSCluster, query: Application.get_env(:takeaway, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Takeaway.PubSub},
      Takeaway.Elasticsearch.ClusterSetup,
      Takeaway.Elasticsearch.QuestionSync,
      # Start a worker by calling: Takeaway.Worker.start_link(arg)
      # {Takeaway.Worker, arg},
      # Start to serve requests, typically the last entry
      TakeawayWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Takeaway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TakeawayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
