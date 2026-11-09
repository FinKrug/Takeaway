import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :takeaway, Takeaway.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "takeaway_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :takeaway, TakeawayWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "NLhhBx6AHTFLEMv9JUBXa+EO4hWn8t85D4JqItPWOl1SsORuP0rSFHUyRmMMCaR1",
  server: false

# Cheap password hashing keeps the tests fast.
config :takeaway, :pbkdf2_iterations, 1_000

# Print only warnings and errors during test
config :logger, level: :warning

# Tests that check spans attach their own exporter to this simple processor.
config :opentelemetry, processors: [{:otel_simple_processor, %{}}]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Disable automatic background index bootstrapper and question sync, and use Noop indexer during tests
config :takeaway, :elasticsearch, auto_setup: false, auto_sync: false

config :takeaway, :indexer, Takeaway.Indexer.Noop
