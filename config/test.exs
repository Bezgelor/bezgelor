import Config

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
