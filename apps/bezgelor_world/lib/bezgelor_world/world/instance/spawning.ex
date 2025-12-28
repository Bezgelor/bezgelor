defmodule BezgelorWorld.World.Instance.Spawning do
  @moduledoc """
  Spawn loading and management for world instances.

  This module contains pure functions for:
  - Loading spawn definitions from game data
  - Building spawn state structures
  - Tracking spawn definitions

  ## Spawn Loading Process

  When a world instance lazy-loads (first player enters), spawns are loaded:

  1. Creature spawns loaded from `Store.get_creature_spawns/1`
  2. Each spawn definition processed via `spawn_creature_from_def/3`
  3. Harvest nodes loaded separately (see HarvestNodes module)

  ## Spawn Definition Structure

  Creature spawn definitions contain:
  - `creature_id` - The creature template ID
  - `position` - [x, y, z] spawn position
  - `rotation` - [rx, ry, rz] spawn rotation
  - `mode` - Spawn mode (0 = normal, etc.)
  - `active_prop_id` - Optional active prop reference

  ## Integration with Instance

  The Instance GenServer uses this module for spawn operations, while
  maintaining state management responsibilities in the GenServer.
  """

  alias BezgelorWorld.World.CreatureState
  alias BezgelorData.Store

  require Logger

  @type spawn_result :: {:ok, non_neg_integer(), CreatureState.t()} | {:error, term()}
  @type spawn_load_result :: {:ok, map()} | :error

  @doc """
  Load creature spawn data for a world from the data store.

  ## Parameters

  - `world_id` - The world ID to load spawns for

  ## Returns

  `{:ok, zone_data}` with creature_spawns list, or `:error` if not found.
  """
  @spec load_creature_spawns(non_neg_integer()) :: spawn_load_result()
  def load_creature_spawns(world_id) do
    Store.get_creature_spawns(world_id)
  end

  @doc """
  Create a creature from a spawn definition.

  Delegates to CreatureState.build_from_spawn_def/3 for the actual creation.

  ## Parameters

  - `spawn_def` - The spawn definition map
  - `world_id` - The world ID for the creature
  - `spline_index` - Spline index for movement paths

  ## Returns

  `{:ok, guid, creature_state}` on success, `{:error, reason}` on failure.
  """
  @spec spawn_creature_from_def(map(), non_neg_integer(), term()) :: spawn_result()
  def spawn_creature_from_def(spawn_def, world_id, spline_index) do
    CreatureState.build_from_spawn_def(spawn_def, world_id, spline_index)
  end

  @doc """
  Get spawn info for logging purposes.

  ## Parameters

  - `spawn_def` - The spawn definition map

  ## Returns

  A map with creature_id and position for logging.
  """
  @spec spawn_info(map()) :: map()
  def spawn_info(spawn_def) do
    %{
      creature_id: spawn_def.creature_id,
      position: spawn_def.position
    }
  end

  @doc """
  Log a failed spawn attempt.

  ## Parameters

  - `spawn_def` - The spawn definition that failed
  - `reason` - The error reason
  """
  @spec log_spawn_failure(map(), term()) :: :ok
  def log_spawn_failure(spawn_def, reason) do
    Logger.warning(
      "Failed to spawn creature #{spawn_def.creature_id} at #{inspect(spawn_def.position)}: #{inspect(reason)}"
    )
  end

  @doc """
  Log successful spawn loading.

  ## Parameters

  - `count` - Number of spawns loaded
  - `zone_name` - Name of the zone
  - `context` - Optional context string (e.g., "first player entered")
  """
  @spec log_spawn_success(non_neg_integer(), String.t(), String.t() | nil) :: :ok
  def log_spawn_success(count, zone_name, context \\ nil) do
    message =
      if context do
        "Loaded #{count} creature spawns for #{zone_name} (#{context})"
      else
        "Loaded #{count} creature spawns for #{zone_name}"
      end

    Logger.info(message)
  end

  @doc """
  Log when no spawn data is found.

  ## Parameters

  - `zone_name` - Name of the zone
  """
  @spec log_no_spawn_data(String.t()) :: :ok
  def log_no_spawn_data(zone_name) do
    Logger.debug("No spawn data found for #{zone_name}")
  end

  @doc """
  Check if spawns have been loaded for a state.

  ## Parameters

  - `state` - Instance state map with :spawns_loaded key

  ## Returns

  Boolean indicating if spawns are loaded.
  """
  @spec spawns_loaded?(map()) :: boolean()
  def spawns_loaded?(state) do
    Map.get(state, :spawns_loaded, false)
  end

  @doc """
  Mark spawns as loaded in state.

  ## Parameters

  - `state` - Instance state map

  ## Returns

  Updated state with spawns_loaded set to true.
  """
  @spec mark_spawns_loaded(map()) :: map()
  def mark_spawns_loaded(state) do
    %{state | spawns_loaded: true}
  end

  @doc """
  Append spawn definitions to state.

  ## Parameters

  - `state` - Instance state map with :spawn_definitions
  - `new_defs` - List of spawn definitions to append

  ## Returns

  Updated state with appended spawn definitions.
  """
  @spec append_spawn_definitions(map(), [map()]) :: map()
  def append_spawn_definitions(state, new_defs) do
    %{state | spawn_definitions: state.spawn_definitions ++ new_defs}
  end
end
