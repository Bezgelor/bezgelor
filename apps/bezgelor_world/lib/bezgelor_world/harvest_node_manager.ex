defmodule BezgelorWorld.HarvestNodeManager do
  @dialyzer :no_match

  @moduledoc """
  Manages harvest/gathering node spawns in the world.

  ## Overview

  The HarvestNodeManager is responsible for:
  - Spawning harvest nodes from resource_spawns data
  - Tracking node state (available/depleted)
  - Handling node gathering and respawning

  ## Node State

  Each spawned node has:
  - Entity data (GUID, position, display_info)
  - Node type reference (for resource yields)
  - Spawn position (for reference)
  - State (available/depleted)
  - Respawn timer (when depleted)
  """

  use GenServer

  require Logger

  alias BezgelorCore.Entity
  alias BezgelorWorld.WorldManager
  alias BezgelorData.Store

  @type node_state :: %{
          entity: Entity.t(),
          node_type_id: non_neg_integer(),
          spawn_position: {float(), float(), float()},
          spawn_rotation: {float(), float(), float()},
          state: :available | :depleted,
          respawn_timer: reference() | nil,
          respawn_time_ms: non_neg_integer()
        }

  @type state :: %{
          nodes: %{non_neg_integer() => node_state()},
          spawn_definitions: [map()]
        }

  ## Client API

  @doc "Start the HarvestNodeManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Load all harvest node spawns for a zone from static data.
  Returns the number of nodes spawned.
  """
  @spec load_zone_spawns(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_zone_spawns(world_id) do
    GenServer.call(__MODULE__, {:load_zone_spawns, world_id}, 30_000)
  end

  @doc "Get a node by GUID."
  @spec get_node(non_neg_integer()) :: node_state() | nil
  def get_node(guid) do
    GenServer.call(__MODULE__, {:get_node, guid})
  end

  @doc "Get all nodes."
  @spec list_nodes() :: [node_state()]
  def list_nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end

  @doc "Get node count."
  @spec node_count() :: non_neg_integer()
  def node_count do
    GenServer.call(__MODULE__, :node_count)
  end

  @doc """
  Gather from a node. Returns loot and marks node as depleted.
  """
  @spec gather_node(non_neg_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, :not_found | :depleted}
  def gather_node(node_guid, gatherer_guid) do
    GenServer.call(__MODULE__, {:gather_node, node_guid, gatherer_guid})
  end

  @doc "Check if a node is available for gathering."
  @spec node_available?(non_neg_integer()) :: boolean()
  def node_available?(guid) do
    GenServer.call(__MODULE__, {:node_available, guid})
  end

  @doc """
  Clear all spawned nodes. Used for zone reset/shutdown.
  """
  @spec clear_all_nodes() :: :ok
  def clear_all_nodes do
    GenServer.call(__MODULE__, :clear_all_nodes)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      nodes: %{},
      spawn_definitions: []
    }

    Logger.info("HarvestNodeManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:load_zone_spawns, world_id}, _from, state) do
    resource_spawns = Store.get_resource_spawns(world_id)

    if Enum.empty?(resource_spawns) do
      Logger.debug("No resource spawns found for world #{world_id}")
      {:reply, {:ok, 0}, state}
    else
      {spawned_count, new_state} = spawn_from_definitions(resource_spawns, state)
      Logger.info("Loaded #{spawned_count} harvest node spawns for world #{world_id}")
      {:reply, {:ok, spawned_count}, new_state}
    end
  end

  @impl true
  def handle_call({:get_node, guid}, _from, state) do
    {:reply, Map.get(state.nodes, guid), state}
  end

  @impl true
  def handle_call(:list_nodes, _from, state) do
    {:reply, Map.values(state.nodes), state}
  end

  @impl true
  def handle_call(:node_count, _from, state) do
    {:reply, map_size(state.nodes), state}
  end

  @impl true
  def handle_call({:gather_node, node_guid, gatherer_guid}, _from, state) do
    case Map.get(state.nodes, node_guid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{state: :depleted} ->
        {:reply, {:error, :depleted}, state}

      node_state ->
        {result, new_node_state, new_state} = do_gather_node(node_state, gatherer_guid, state)
        nodes = Map.put(state.nodes, node_guid, new_node_state)
        {:reply, result, %{new_state | nodes: nodes}}
    end
  end

  @impl true
  def handle_call({:node_available, guid}, _from, state) do
    result =
      case Map.get(state.nodes, guid) do
        nil -> false
        %{state: :available} -> true
        _ -> false
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear_all_nodes, _from, state) do
    # Cancel any pending respawn timers
    for {_guid, %{respawn_timer: timer}} <- state.nodes, timer != nil do
      Process.cancel_timer(timer)
    end

    Logger.info("Cleared #{map_size(state.nodes)} harvest nodes")
    {:reply, :ok, %{state | nodes: %{}, spawn_definitions: []}}
  end

  @impl true
  def handle_info({:respawn_node, guid}, state) do
    state =
      case Map.get(state.nodes, guid) do
        nil ->
          state

        node_state ->
          # Respawn the node
          new_node_state = %{
            node_state
            | state: :available,
              respawn_timer: nil
          }

          Logger.debug("Respawned harvest node #{guid}")
          %{state | nodes: Map.put(state.nodes, guid, new_node_state)}
      end

    {:noreply, state}
  end

  ## Private Functions

  defp do_gather_node(node_state, _gatherer_guid, state) do
    # Get node type info for loot generation
    node_type_id = node_state.node_type_id
    loot = generate_node_loot(node_type_id)

    # Schedule respawn
    respawn_timer = Process.send_after(
      self(),
      {:respawn_node, node_state.entity.guid},
      node_state.respawn_time_ms
    )

    new_node_state = %{
      node_state
      | state: :depleted,
        respawn_timer: respawn_timer
    }

    Logger.debug(
      "Node #{node_state.entity.guid} gathered, respawning in #{node_state.respawn_time_ms}ms"
    )

    {{:ok, loot}, new_node_state, state}
  end

  defp generate_node_loot(harvest_node_id) do
    # Look up the harvest loot by creature ID
    case Store.get_harvest_loot(harvest_node_id) do
      {:ok, loot_data} ->
        loot = get_map_value(loot_data, :loot, %{})
        primary = get_map_value(loot, :primary, [])
        secondary = get_map_value(loot, :secondary, [])

        # Always generate primary drops
        primary_loot =
          Enum.flat_map(primary, fn drop ->
            roll_drop(drop)
          end)

        # Roll for secondary drops (chance-based)
        secondary_loot =
          Enum.flat_map(secondary, fn drop ->
            chance = get_map_value(drop, :chance, 0.0)

            if :rand.uniform() <= chance do
              roll_drop(drop)
            else
              []
            end
          end)

        primary_loot ++ secondary_loot

      :error ->
        # Fallback - generic material
        Logger.warning("No harvest loot found for node #{harvest_node_id}, using fallback")
        [%{item_id: 0, name: "Unknown Resource", quantity: 1}]
    end
  end

  # Roll a drop with quantity range
  defp roll_drop(drop) do
    item_id = get_map_value(drop, :item_id, 0)
    name = get_map_value(drop, :name, "Unknown")
    min_qty = get_map_value(drop, :min, 1)
    max_qty = get_map_value(drop, :max, 1)

    quantity =
      if max_qty > min_qty do
        Enum.random(min_qty..max_qty)
      else
        min_qty
      end

    [%{item_id: item_id, name: name, quantity: quantity}]
  end

  # Helper to handle both atom and string keys in maps (from JSON parsing)
  defp get_map_value(map, key, default) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key), default)
      value -> value
    end
  end

  # Spawn nodes from static data definitions
  defp spawn_from_definitions(spawn_defs, state) do
    # Store definitions for reference
    state = %{state | spawn_definitions: state.spawn_definitions ++ spawn_defs}

    # Spawn each node
    {spawned_count, nodes} =
      Enum.reduce(spawn_defs, {0, state.nodes}, fn spawn_def, {count, nodes} ->
        {:ok, guid, node_state} = spawn_node_from_def(spawn_def)
        {count + 1, Map.put(nodes, guid, node_state)}
      end)

    {spawned_count, %{state | nodes: nodes}}
  end

  # Spawn a single harvest node from a spawn definition
  defp spawn_node_from_def(spawn_def) do
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    [rx, ry, rz] = spawn_def.rotation
    rotation = {rx, ry, rz}

    guid = WorldManager.generate_guid(:object)

    # Get node type name for entity name
    node_name =
      case Store.get_node_type(spawn_def.node_type_id) do
        {:ok, node_type} -> node_type[:name] || "Harvest Node"
        :error -> "Harvest Node"
      end

    entity = %Entity{
      guid: guid,
      type: :object,
      name: node_name,
      display_info: spawn_def.display_info,
      faction: 0,
      level: 1,
      position: position,
      rotation: rotation,
      health: 1,
      max_health: 1
    }

    node_state = %{
      entity: entity,
      node_type_id: spawn_def.node_type_id,
      spawn_position: position,
      spawn_rotation: rotation,
      state: :available,
      respawn_timer: nil,
      respawn_time_ms: spawn_def.respawn_time_ms || 60_000
    }

    Logger.debug(
      "Spawned harvest node #{node_name} (#{guid}) at #{inspect(position)}"
    )

    {:ok, guid, node_state}
  end
end
