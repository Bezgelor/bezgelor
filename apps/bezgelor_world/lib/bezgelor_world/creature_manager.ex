defmodule BezgelorWorld.CreatureManager do
  @moduledoc """
  DEPRECATED: Facade for backward compatibility during per-zone migration.

  This module now routes all calls to the appropriate World.Instance.
  Callers should migrate to using World.Instance directly.

  ## Migration Guide

  Replace CreatureManager calls with World.Instance calls:

  | Old API | New API |
  |---------|---------|
  | `CreatureManager.get_creature(guid)` | `World.Instance.get_creature({world_id, 1}, guid)` |
  | `CreatureManager.damage_creature(guid, attacker, dmg)` | `World.Instance.damage_creature({world_id, 1}, guid, attacker, dmg)` |
  | `CreatureManager.creature_targetable?(guid)` | `World.Instance.creature_targetable?({world_id, 1}, guid)` |
  | `CreatureManager.get_creatures_in_range(pos, range)` | `World.Instance.get_creatures_in_range({world_id, 1}, pos, range)` |

  The key difference is that World.Instance methods require a `{world_id, instance_id}` tuple.
  """

  require Logger

  alias BezgelorWorld.World.Instance, as: WorldInstance
  alias BezgelorWorld.World.InstanceSupervisor

  @deprecated "Use World.Instance.get_creature/2 instead"
  @spec get_creature(non_neg_integer()) :: map() | nil
  def get_creature(guid) do
    # Search all instances for this creature
    # This is inefficient but maintains backward compatibility
    find_creature_in_instances(guid)
  end

  @deprecated "Use World.Instance.list_creatures/1 instead"
  @spec list_creatures() :: [map()]
  def list_creatures do
    # Aggregate creatures from all instances
    InstanceSupervisor.list_instances()
    |> Enum.flat_map(fn {world_id, instance_id, _pid} ->
      try do
        WorldInstance.list_creatures({world_id, instance_id})
      catch
        :exit, _ -> []
      end
    end)
  end

  @deprecated "Use World.Instance.get_creatures_in_range/3 instead"
  @spec get_creatures_in_range({float(), float(), float()}, float()) :: [map()]
  def get_creatures_in_range(position, range) do
    # Aggregate from all instances - caller should use World.Instance directly
    Logger.warning(
      "CreatureManager.get_creatures_in_range/2 is deprecated - use World.Instance.get_creatures_in_range/3"
    )

    InstanceSupervisor.list_instances()
    |> Enum.flat_map(fn {world_id, instance_id, _pid} ->
      try do
        WorldInstance.get_creatures_in_range({world_id, instance_id}, position, range)
      catch
        :exit, _ -> []
      end
    end)
  end

  @deprecated "Use World.Instance.damage_creature/4 instead"
  @spec damage_creature(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, :damaged | :killed, map()} | {:error, term()}
  def damage_creature(creature_guid, attacker_guid, damage) do
    case find_creature_instance(creature_guid) do
      {:ok, world_key} ->
        WorldInstance.damage_creature(world_key, creature_guid, attacker_guid, damage)

      :error ->
        {:error, :creature_not_found}
    end
  end

  @deprecated "Use World.Instance.creature_enter_combat/3 instead"
  @spec creature_enter_combat(non_neg_integer(), non_neg_integer()) :: :ok
  def creature_enter_combat(creature_guid, target_guid) do
    case find_creature_instance(creature_guid) do
      {:ok, world_key} ->
        WorldInstance.creature_enter_combat(world_key, creature_guid, target_guid)

      :error ->
        :ok
    end
  end

  @deprecated "Use World.Instance.creature_targetable?/2 instead"
  @spec creature_targetable?(non_neg_integer()) :: boolean()
  def creature_targetable?(guid) do
    case find_creature_instance(guid) do
      {:ok, world_key} ->
        WorldInstance.creature_targetable?(world_key, guid)

      :error ->
        false
    end
  end

  @deprecated "Use World.Instance.creature_count/1 instead"
  @spec creature_count() :: non_neg_integer()
  def creature_count do
    InstanceSupervisor.list_instances()
    |> Enum.reduce(0, fn {world_id, instance_id, _pid}, acc ->
      try do
        acc + WorldInstance.creature_count({world_id, instance_id})
      catch
        :exit, _ -> acc
      end
    end)
  end

  @doc """
  DEPRECATED: Spawn loading is now handled automatically by World.Instance.

  This function is a no-op and returns {:ok, 0} immediately.
  World.Instance loads spawns during its initialization.
  """
  @deprecated "Spawn loading is automatic - no action needed"
  @spec load_zone_spawns(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_zone_spawns(_world_id) do
    # No-op - spawns are loaded automatically by World.Instance
    {:ok, 0}
  end

  @deprecated "Spawn loading is automatic - no action needed"
  @spec load_zone_spawns_async(non_neg_integer()) :: :ok
  def load_zone_spawns_async(_world_id) do
    # No-op - spawns are loaded automatically by World.Instance
    :ok
  end

  @deprecated "Use World.Instance.spawn_creature/3 instead"
  @spec spawn_creature(non_neg_integer(), {float(), float(), float()}) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def spawn_creature(template_id, position) do
    # Default to world 1, instance 1 for backward compatibility
    WorldInstance.spawn_creature({1, 1}, template_id, position)
  end

  # Private helpers

  defp find_creature_in_instances(guid) do
    InstanceSupervisor.list_instances()
    |> Enum.find_value(fn {world_id, instance_id, _pid} ->
      try do
        WorldInstance.get_creature({world_id, instance_id}, guid)
      catch
        :exit, _ -> nil
      end
    end)
  end

  defp find_creature_instance(guid) do
    InstanceSupervisor.list_instances()
    |> Enum.find_value(fn {world_id, instance_id, _pid} ->
      try do
        case WorldInstance.get_creature({world_id, instance_id}, guid) do
          nil -> nil
          _creature -> {:ok, {world_id, instance_id}}
        end
      catch
        :exit, _ -> nil
      end
    end)
    |> case do
      nil -> :error
      result -> result
    end
  end
end
