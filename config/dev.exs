import Config

# Development-specific Repo configuration
config :bezgelor_db, BezgelorDb.Repo,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true
