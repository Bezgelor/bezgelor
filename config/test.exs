import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bezgelor_portal, BezgelorPortalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jDrJpVd8YZ7YWnz7ItQqfszsv++I/eX/LNs4l39qGUvh2egs939PwhoG2PqJxM2z",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Test database configuration
config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_test#{System.get_env("MIX_TEST_PARTITION")}",
  username: System.get_env("POSTGRES_USER", "bezgelor"),
  password: System.get_env("POSTGRES_PASSWORD", "bezgelor_dev"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5433")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Don't start servers during tests
config :bezgelor_auth, start_server: false
config :bezgelor_api, start_server: false
config :bezgelor_realm, start_server: false
config :bezgelor_world, start_server: false

# Don't start telemetry collectors during tests (they're started manually in tests)
config :bezgelor_portal, start_telemetry_collector: false
config :bezgelor_portal, start_rollup_scheduler: false

config :logger, level: :warning
