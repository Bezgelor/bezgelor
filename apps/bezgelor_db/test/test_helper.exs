# Exclude database tests (need running PostgreSQL) and pending implementation tests
ExUnit.start(exclude: [:database, :pending_implementation, :skip])

# Compile support modules
Code.compile_file("test/support/test_helpers.ex", __DIR__ |> Path.dirname())

# Start the repo for database tests
{:ok, _} = Application.ensure_all_started(:ecto_sql)

# Setup sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(BezgelorDb.Repo, :manual)
