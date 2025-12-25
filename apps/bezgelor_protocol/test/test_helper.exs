# Exclude tests that require bezgelor_world when running in isolation
# These tests need DeathManager, Teleport, and WorldManager which are GenServers
# in bezgelor_world. When running the full umbrella test suite, these are available.
exclude_tags = [:database, :integration]

# Check if bezgelor_world application is available
world_available? =
  case Application.ensure_all_started(:bezgelor_world) do
    {:ok, _} -> true
    {:error, _} -> false
  end

exclude_tags =
  if world_available? do
    exclude_tags
  else
    [:requires_world | exclude_tags]
  end

ExUnit.start(exclude: exclude_tags)
