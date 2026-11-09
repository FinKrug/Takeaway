# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :takeaway,
  env: config_env(),
  ecto_repos: [Takeaway.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :takeaway, TakeawayWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TakeawayWeb.ErrorHTML, json: TakeawayWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Takeaway.PubSub,
  live_view: [signing_salt: "ewRGLq6k"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  takeaway: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  takeaway: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Elasticsearch
config :takeaway, :elasticsearch,
  url: "http://localhost:9200",
  api_key: nil
# OpenTelemetry. Nothing is exported unless config/runtime.exs switches the
# OTLP exporter on (DASH0_AUTH_TOKEN set). Kubernetes probe requests are never
# traced (Takeaway.OtelSampler).
config :opentelemetry,
  traces_exporter: :none,
  sampler: {:parent_based, %{root: {Takeaway.OtelSampler, %{}}}},
  resource: %{service: %{name: "takeaway"}}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
