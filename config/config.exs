import Config

config :bezgelor_db,
  ecto_repos: [BezgelorDb.Repo]

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10

import_config "#{config_env()}.exs"
