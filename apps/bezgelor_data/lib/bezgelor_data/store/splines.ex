defmodule BezgelorData.Store.Splines do
  @moduledoc """
  Spline and patrol path-related data queries for the Store.

  Provides functions for querying patrol paths, splines, spline nodes,
  and entity spline configurations.

  ## Patrol Paths

  Patrol paths are pre-defined waypoint sequences that NPCs follow.
  They have names, waypoints with positions and pause times.

  ## Splines

  Splines are from WildStar's Spline2.tbl and Spline2Node.tbl tables.
  They define curved paths with waypoints (nodes) that entities can follow.

  ## Entity Splines

  Entity splines map specific creatures at specific positions to their
  assigned spline paths, including movement mode and speed.
  """

  alias BezgelorData.Store.{Core, Index}

  # Patrol Path queries

  @doc """
  Get a patrol path by name.
  """
  @spec get_patrol_path(String.t()) :: {:ok, map()} | :error
  def get_patrol_path(path_name) do
    case :ets.lookup(Core.table_name(:patrol_paths), path_name) do
      [{^path_name, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  Get all patrol paths.
  """
  @spec list_patrol_paths() :: [map()]
  def list_patrol_paths do
    Core.table_name(:patrol_paths)
    |> :ets.tab2list()
    |> Enum.map(fn {_name, data} -> data end)
  end

  # Spline queries (from WildStar client Spline2.tbl / Spline2Node.tbl)

  @doc """
  Get a spline definition by ID.
  Returns the spline with its waypoints (nodes).
  """
  @spec get_spline(non_neg_integer()) :: {:ok, map()} | :error
  def get_spline(spline_id) do
    case Core.get(:splines, spline_id) do
      {:ok, spline} ->
        nodes = get_spline_nodes(spline_id)
        {:ok, Map.put(spline, :nodes, nodes)}

      :error ->
        :error
    end
  end

  @doc """
  Get spline nodes for a spline ID.
  Returns nodes sorted by ordinal (waypoint order).
  """
  @spec get_spline_nodes(non_neg_integer()) :: [map()]
  def get_spline_nodes(spline_id) do
    ids = Index.lookup_index(:spline_nodes_by_spline, spline_id)

    Index.fetch_by_ids(:spline_nodes, ids)
    |> Enum.sort_by(& &1.ordinal)
  end

  @doc """
  Get all splines for a world/zone.
  """
  @spec get_splines_for_world(non_neg_integer()) :: [map()]
  def get_splines_for_world(world_id) do
    Core.list(:splines)
    |> Enum.filter(fn s -> s.world_id == world_id end)
  end

  @doc """
  Find the nearest spline to a position in a given world.
  Returns {:ok, spline_id, distance} if found within max_distance, :none otherwise.

  Options:
    - max_distance: maximum distance to search (default: 5.0 units)
  """
  @spec find_nearest_spline(non_neg_integer(), {float(), float(), float()}, keyword()) ::
          {:ok, non_neg_integer(), float()} | :none
  def find_nearest_spline(world_id, {px, py, pz} = _position, opts \\ []) do
    max_distance = Keyword.get(opts, :max_distance, 5.0)

    # Get all splines for this world with their first node position
    splines_with_start =
      get_splines_for_world(world_id)
      |> Enum.map(fn spline ->
        nodes = get_spline_nodes(spline.id)

        case nodes do
          [first | _] ->
            {spline.id, {first.position0, first.position1, first.position2}}

          [] ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Find the closest spline by distance to first waypoint
    result =
      splines_with_start
      |> Enum.map(fn {spline_id, {sx, sy, sz}} ->
        distance =
          :math.sqrt(:math.pow(px - sx, 2) + :math.pow(py - sy, 2) + :math.pow(pz - sz, 2))

        {spline_id, distance}
      end)
      |> Enum.filter(fn {_id, dist} -> dist <= max_distance end)
      |> Enum.min_by(fn {_id, dist} -> dist end, fn -> nil end)

    case result do
      {spline_id, distance} -> {:ok, spline_id, distance}
      nil -> :none
    end
  end

  @doc """
  Build a spatial index of spline starting positions for efficient lookups.
  Returns a map of %{world_id => [{spline_id, {x, y, z}}]}.
  """
  @spec build_spline_spatial_index() :: map()
  def build_spline_spatial_index do
    Core.list(:splines)
    |> Enum.reduce(%{}, fn spline, acc ->
      nodes = get_spline_nodes(spline.id)

      case nodes do
        [first | _] ->
          entry = {spline.id, {first.position0, first.position1, first.position2}}
          world_entries = Map.get(acc, spline.world_id, [])
          Map.put(acc, spline.world_id, [entry | world_entries])

        [] ->
          acc
      end
    end)
  end

  @doc """
  Find nearest spline using a pre-built spatial index (more efficient for batch lookups).
  """
  @spec find_nearest_spline_indexed(
          map(),
          non_neg_integer(),
          {float(), float(), float()},
          keyword()
        ) ::
          {:ok, non_neg_integer(), float()} | :none
  def find_nearest_spline_indexed(spatial_index, world_id, {px, py, pz}, opts \\ []) do
    max_distance = Keyword.get(opts, :max_distance, 5.0)

    case Map.get(spatial_index, world_id, []) do
      [] ->
        :none

      splines ->
        result =
          splines
          |> Enum.map(fn {spline_id, {sx, sy, sz}} ->
            distance =
              :math.sqrt(:math.pow(px - sx, 2) + :math.pow(py - sy, 2) + :math.pow(pz - sz, 2))

            {spline_id, distance}
          end)
          |> Enum.filter(fn {_id, dist} -> dist <= max_distance end)
          |> Enum.min_by(fn {_id, dist} -> dist end, fn -> nil end)

        case result do
          {spline_id, distance} -> {:ok, spline_id, distance}
          nil -> :none
        end
    end
  end

  @doc """
  Get spline as patrol path format (compatible with AI patrol system).
  Converts spline nodes to waypoints with position and pause_ms.
  """
  @spec get_spline_as_patrol(non_neg_integer()) :: {:ok, map()} | :error
  def get_spline_as_patrol(spline_id) do
    case get_spline(spline_id) do
      {:ok, spline} ->
        waypoints =
          Enum.map(spline.nodes, fn node ->
            %{
              position: {node.position0, node.position1, node.position2},
              pause_ms: trunc(node.delay * 1000)
            }
          end)

        patrol = %{
          name: "spline_#{spline_id}",
          display_name: "Spline #{spline_id}",
          world_id: spline.world_id,
          spline_type: spline.spline_type,
          waypoints: waypoints,
          mode: :cyclic,
          speed: 3.0
        }

        {:ok, patrol}

      :error ->
        :error
    end
  end

  @doc """
  Look up entity spline configuration by world_id, creature_id, and position.

  Returns {:ok, spline_config} if a matching entity spline is found, :none otherwise.
  Matches entities within 5 units of the given position (to handle minor coordinate differences).

  The spline_config contains:
  - spline_id: The spline path to follow
  - mode: SplineMode (0=OneShot, 1=BackAndForth, 2=Cyclic, etc.)
  - speed: Movement speed (units/second), -1 means use default
  - fx, fy, fz: Formation offsets from path
  """
  @spec find_entity_spline(non_neg_integer(), non_neg_integer(), {float(), float(), float()}) ::
          {:ok, map()} | :none
  def find_entity_spline(world_id, creature_id, {px, py, pz}) do
    table_name = Core.table_name(:entity_splines)

    case :ets.lookup(table_name, world_id) do
      [{^world_id, entities}] ->
        # Find entity matching creature_id and position (within tolerance)
        match =
          Enum.find(entities, fn entity ->
            entity_creature_id = entity[:creature_id] || entity["creature_id"]
            position = entity[:position] || entity["position"]

            # Handle both list and tuple positions
            {ex, ey, ez} =
              case position do
                [x, y, z] -> {x, y, z}
                {x, y, z} -> {x, y, z}
                _ -> {0, 0, 0}
              end

            entity_creature_id == creature_id and
              position_match?({px, py, pz}, {ex, ey, ez}, 5.0)
          end)

        case match do
          nil ->
            :none

          entity ->
            spline = entity[:spline] || entity["spline"]
            {:ok, normalize_spline_config(spline)}
        end

      [] ->
        :none
    end
  end

  # Private helpers

  # Check if two positions are within distance of each other
  defp position_match?({x1, y1, z1}, {x2, y2, z2}, max_dist) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz) <= max_dist
  end

  # Normalize spline config from JSON (handles both atom and string keys)
  defp normalize_spline_config(spline) do
    %{
      spline_id: spline[:spline_id] || spline["spline_id"],
      mode: spline[:mode] || spline["mode"],
      speed: spline[:speed] || spline["speed"],
      fx: spline[:fx] || spline["fx"] || 0,
      fy: spline[:fy] || spline["fy"] || 0,
      fz: spline[:fz] || spline["fz"] || 0
    }
  end
end
