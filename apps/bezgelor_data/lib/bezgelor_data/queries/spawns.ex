defmodule BezgelorData.Queries.Spawns do
  @moduledoc """
  Query functions for spawn data: creatures, resources, objects, bindpoints.
  """

  alias BezgelorData.Store

  # Creature spawn queries

  @doc """
  Get creature spawns for a world/zone.
  Returns a map with creature_spawns, resource_spawns, and object_spawns.
  """
  @spec get_creature_spawns(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_spawns(world_id), do: Store.get(:creature_spawns, world_id)

  @doc """
  Get all zone spawn data.
  """
  @spec get_all_spawn_zones() :: [map()]
  def get_all_spawn_zones, do: Store.list(:creature_spawns)

  @doc """
  Get creature spawns for a specific area within a zone.
  """
  @spec get_spawns_in_area(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_spawns_in_area(world_id, area_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        Enum.filter(zone_data.creature_spawns, fn spawn ->
          spawn.area_id == area_id
        end)

      :error ->
        []
    end
  end

  @doc """
  Get all spawns for a specific creature template ID across all zones.
  """
  @spec get_spawns_for_creature(non_neg_integer()) :: [map()]
  def get_spawns_for_creature(creature_id) do
    Store.list(:creature_spawns)
    |> Enum.flat_map(fn zone_data ->
      Enum.filter(zone_data.creature_spawns, fn spawn ->
        spawn.creature_id == creature_id
      end)
    end)
  end

  @doc """
  Get resource spawns for a world/zone.
  """
  @spec get_resource_spawns(non_neg_integer()) :: [map()]
  def get_resource_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.resource_spawns
      :error -> []
    end
  end

  @doc """
  Get object spawns for a world/zone.
  """
  @spec get_object_spawns(non_neg_integer()) :: [map()]
  def get_object_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.object_spawns
      :error -> []
    end
  end

  @doc """
  Get spawn count for a world/zone.
  """
  @spec get_spawn_count(non_neg_integer()) :: non_neg_integer()
  def get_spawn_count(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        length(zone_data.creature_spawns) +
          length(zone_data.resource_spawns) +
          length(zone_data.object_spawns)

      :error ->
        0
    end
  end

  @doc """
  Get total spawn count across all zones.
  """
  @spec get_total_spawn_count() :: non_neg_integer()
  def get_total_spawn_count do
    Store.list(:creature_spawns)
    |> Enum.reduce(0, fn zone_data, acc ->
      acc +
        length(zone_data.creature_spawns) +
        length(zone_data.resource_spawns) +
        length(zone_data.object_spawns)
    end)
  end

  # Bindpoint/Graveyard queries

  @doc """
  Get all bindpoint spawns.
  """
  @spec get_all_bindpoints() :: [map()]
  def get_all_bindpoints do
    # Data is stored as {world_id, [bindpoints]} - flatten to single list
    Store.list(:bindpoint_spawns)
    |> List.flatten()
  end

  @doc """
  Get bindpoint spawns for a specific world.
  """
  @spec get_bindpoints_for_world(non_neg_integer()) :: [map()]
  def get_bindpoints_for_world(world_id) do
    case Store.get(:bindpoint_spawns, world_id) do
      {:ok, bindpoints} -> bindpoints
      :error -> []
    end
  end

  @doc """
  Find the nearest bindpoint to a position in a world.
  Returns the bindpoint spawn data or nil if none found.
  """
  @spec find_nearest_bindpoint(non_neg_integer(), {float(), float(), float()}) ::
          map() | nil
  def find_nearest_bindpoint(world_id, {x, y, z}) do
    get_bindpoints_for_world(world_id)
    |> Enum.map(fn bp ->
      [bx, by, bz] = bp.position
      distance = :math.sqrt(:math.pow(x - bx, 2) + :math.pow(y - by, 2) + :math.pow(z - bz, 2))
      {distance, bp}
    end)
    |> Enum.min_by(fn {distance, _bp} -> distance end, fn -> nil end)
    |> case do
      nil -> nil
      {_distance, bp} -> bp
    end
  end

  @doc """
  Get bindpoint data by bindpoint ID (links to creatures with bindPointId).
  """
  @spec get_bindpoint_by_creature_id(non_neg_integer()) :: map() | nil
  def get_bindpoint_by_creature_id(creature_id) do
    get_all_bindpoints()
    |> Enum.find(fn bp -> bp.bindpoint_id == creature_id end)
  end
end
