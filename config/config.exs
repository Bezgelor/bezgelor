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

# Auth Server (STS) configuration
config :bezgelor_auth,
  port: String.to_integer(System.get_env("AUTH_PORT", "6600"))

# Realm Server configuration
config :bezgelor_realm,
  port: String.to_integer(System.get_env("REALM_PORT", "23115"))

# World Server configuration
config :bezgelor_world,
  port: String.to_integer(System.get_env("WORLD_PORT", "24000"))

import_config "#{config_env()}.exs"
