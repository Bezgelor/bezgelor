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

# Tradeskill configuration
config :bezgelor_world, :tradeskills,
  # Profession limits (0 = unlimited)
  max_crafting_professions: 2,
  max_gathering_professions: 3,
  preserve_progress_on_swap: false,

  # Discovery scope - :character or :account
  discovery_scope: :character,

  # Node competition mode - :first_tap, :shared, or :instanced
  node_competition: :first_tap,
  shared_tap_window_seconds: 5,

  # Tech tree respec policy - :free, :gold_cost, :item_required, or :disabled
  respec_policy: :gold_cost,
  respec_gold_cost: 10_00,
  respec_item_id: nil,

  # Crafting station mode - :strict, :universal, or :housing_bypass
  station_mode: :strict

import_config "#{config_env()}.exs"
