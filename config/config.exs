# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bezgelor_portal,
  generators: [timestamp_type: :utc_datetime]

# Swoosh mailer configuration
config :bezgelor_portal, BezgelorPortal.Mailer,
  adapter: Swoosh.Adapters.Local

# Hammer rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Cloak vault for encrypting sensitive data (TOTP secrets)
# Generate a key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
config :bezgelor_portal, BezgelorPortal.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.get_env("CLOAK_KEY", "dGVzdF9rZXlfMzJfYnl0ZXNfbG9uZ19mb3JfYWVzXw=="))
    }
  ]

# Configure the endpoint
config :bezgelor_portal, BezgelorPortalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BezgelorPortalWeb.ErrorHTML, json: BezgelorPortalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BezgelorPortal.PubSub,
  live_view: [signing_salt: "eKZa3Jmc"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bezgelor_portal: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/bezgelor_portal/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  bezgelor_portal: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/bezgelor_portal", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

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
  host: System.get_env("AUTH_HOST", "0.0.0.0"),
  port: String.to_integer(System.get_env("AUTH_PORT", "6600"))

# Realm Server configuration
config :bezgelor_realm,
  host: System.get_env("REALM_HOST", "0.0.0.0"),
  port: String.to_integer(System.get_env("REALM_PORT", "23115")),
  # Realm info sent to clients
  realm_name: System.get_env("REALM_NAME", "Bezgelor"),
  realm_type: :pve,  # :pve or :pvp
  realm_flags: 0,
  realm_note_text_id: 0

# World Server configuration
config :bezgelor_world,
  host: System.get_env("WORLD_HOST", "0.0.0.0"),
  port: String.to_integer(System.get_env("WORLD_PORT", "24000")),
  # Public address clients connect to (defaults to host if not set)
  public_address: System.get_env("WORLD_PUBLIC_ADDRESS", "127.0.0.1")

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
