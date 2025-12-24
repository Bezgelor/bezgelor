defmodule BezgelorWorld.HarvestNodeManager do
  @moduledoc """
  DEPRECATED: Facade for backward compatibility during per-zone migration.

  This module now routes all calls to the appropriate World.Instance.
  Callers should migrate to using World.Instance directly.

  ## Migration Guide

  Replace HarvestNodeManager calls with World.Instance calls:

  | Old API | New API |
  |---------|---------|
  | `HarvestNodeManager.get_node(guid)` | `World.Instance.get_harvest_node({world_id, 1}, guid)` |
  | `HarvestNodeManager.gather_node(guid, gatherer)` | `World.Instance.gather_harvest_node({world_id, 1}, guid, gatherer)` |
  | `HarvestNodeManager.node_available?(guid)` | `World.Instance.harvest_node_available?({world_id, 1}, guid)` |
  | `HarvestNodeManager.list_nodes()` | `World.Instance.list_harvest_nodes({world_id, 1})` |
  | `HarvestNodeManager.node_count()` | `World.Instance.harvest_node_count({world_id, 1})` |

  The key difference is that World.Instance methods require a `{world_id, instance_id}` tuple.
  """

  require Logger

  alias BezgelorWorld.World.Instance, as: WorldInstance
  alias BezgelorWorld.World.InstanceSupervisor

  @deprecated "Use World.Instance.get_harvest_node/2 instead"
  @spec get_node(non_neg_integer()) :: map() | nil
  def get_node(guid) do
    # Search all instances for this harvest node
    find_node_in_instances(guid)
  end

  @deprecated "Use World.Instance.list_harvest_nodes/1 instead"
  @spec list_nodes() :: [map()]
  def list_nodes do
    # Aggregate nodes from all instances
    InstanceSupervisor.list_instances()
    |> Enum.flat_map(fn {world_id, instance_id, _pid} ->
      try do
        WorldInstance.list_harvest_nodes({world_id, instance_id})
      catch
        :exit, _ -> []
      end
    end)
  end

  @deprecated "Use World.Instance.harvest_node_count/1 instead"
  @spec node_count() :: non_neg_integer()
  def node_count do
    InstanceSupervisor.list_instances()
    |> Enum.reduce(0, fn {world_id, instance_id, _pid}, acc ->
      try do
        acc + WorldInstance.harvest_node_count({world_id, instance_id})
      catch
        :exit, _ -> acc
      end
    end)
  end

  @deprecated "Use World.Instance.gather_harvest_node/3 instead"
  @spec gather_node(non_neg_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, :not_found | :depleted}
  def gather_node(node_guid, gatherer_guid) do
    Logger.warning(
      "HarvestNodeManager.gather_node/2 is deprecated - use World.Instance.gather_harvest_node/3"
    )

    # Find which instance has this node and delegate
    case find_node_instance(node_guid) do
      nil ->
        {:error, :not_found}

      {world_id, instance_id} ->
        WorldInstance.gather_harvest_node({world_id, instance_id}, node_guid, gatherer_guid)
    end
  end

  @deprecated "Use World.Instance.harvest_node_available?/2 instead"
  @spec node_available?(non_neg_integer()) :: boolean()
  def node_available?(guid) do
    # Search all instances
    InstanceSupervisor.list_instances()
    |> Enum.any?(fn {world_id, instance_id, _pid} ->
      try do
        WorldInstance.harvest_node_available?({world_id, instance_id}, guid)
      catch
        :exit, _ -> false
      end
    end)
  end

  @deprecated "Harvest nodes are now loaded per-zone in World.Instance"
  @spec load_zone_spawns(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_zone_spawns(_world_id) do
    Logger.warning(
      "HarvestNodeManager.load_zone_spawns/1 is deprecated - spawns are now loaded per-zone in World.Instance"
    )

    {:ok, 0}
  end

  @deprecated "Harvest nodes are now loaded per-zone in World.Instance"
  @spec load_zone_spawns_async(non_neg_integer()) :: :ok
  def load_zone_spawns_async(_world_id) do
    Logger.warning(
      "HarvestNodeManager.load_zone_spawns_async/1 is deprecated - spawns are now loaded per-zone in World.Instance"
    )

    :ok
  end

  @deprecated "Use World.Instance lifecycle management instead"
  @spec clear_all_nodes() :: :ok
  def clear_all_nodes do
    Logger.warning(
      "HarvestNodeManager.clear_all_nodes/0 is deprecated - nodes are cleared when World.Instance stops"
    )

    :ok
  end

  # Private helper to find a node across all instances
  defp find_node_in_instances(guid) do
    InstanceSupervisor.list_instances()
    |> Enum.find_value(fn {world_id, instance_id, _pid} ->
      try do
        case WorldInstance.get_harvest_node({world_id, instance_id}, guid) do
          nil -> nil
          node -> node
        end
      catch
        :exit, _ -> nil
      end
    end)
  end

  # Private helper to find which instance has a node
  defp find_node_instance(guid) do
    InstanceSupervisor.list_instances()
    |> Enum.find_value(fn {world_id, instance_id, _pid} ->
      try do
        case WorldInstance.get_harvest_node({world_id, instance_id}, guid) do
          nil -> nil
          _node -> {world_id, instance_id}
        end
      catch
        :exit, _ -> nil
      end
    end)
  end
end
