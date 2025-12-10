# Don't start the application during tests
Application.put_env(:bezgelor_realm, :start_server, false)

# Exclude database and integration tests by default
ExUnit.start(exclude: [:database, :integration])

# Setup sandbox mode for database tests
Ecto.Adapters.SQL.Sandbox.mode(BezgelorDb.Repo, :manual)
