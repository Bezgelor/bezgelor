import Config

config :bezgelor_db,
  ecto_repos: [BezgelorDb.Repo]

# Default database config - overridden per environment
config :bezgelor_db, BezgelorDb.Repo,
  database: System.get_env("POSTGRES_DB", "bezgelor_dev"),
  username: System.get_env("POSTGRES_USER", "bezgelor"),
  password: System.get_env("POSTGRES_PASSWORD", "bezgelor_dev"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5433")),
  pool_size: 10

import_config "#{config_env()}.exs"
