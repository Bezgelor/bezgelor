ExUnit.start(exclude: [:database])

# Start the repo for database tests
{:ok, _} = Application.ensure_all_started(:ecto_sql)

# Setup sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(BezgelorDb.Repo, :manual)
