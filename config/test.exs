import Config

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
config :bezgelor_realm, start_server: false
config :bezgelor_world, start_server: false

config :logger, level: :warning
