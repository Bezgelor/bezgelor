defmodule BezgelorDb.Repo do
  @moduledoc """
  Main database repository for Bezgelor.

  ## Overview

  This is the primary Ecto Repo for all database operations. It connects
  to PostgreSQL and handles:

  - Account data (users, permissions, roles)
  - Character data (characters, items, quests)
  - World data (guilds, chat channels)

  ## Configuration

  Configure in `config/config.exs`:

      config :bezgelor_db, BezgelorDb.Repo,
        database: "bezgelor_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        pool_size: 10
  """

  use Ecto.Repo,
    otp_app: :bezgelor_db,
    adapter: Ecto.Adapters.Postgres
end
