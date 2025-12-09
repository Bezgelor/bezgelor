import Config

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
