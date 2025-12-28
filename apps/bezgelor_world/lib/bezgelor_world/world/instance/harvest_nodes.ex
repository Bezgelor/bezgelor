defmodule BezgelorWorld.World.Instance.HarvestNodes do
  @moduledoc """
  Harvest node spawning and loot generation for world instances.

  This module contains pure functions for:
  - Loading harvest node spawn data
  - Creating harvest node state
  - Generating loot from gathered nodes
  - Managing node availability state

  ## Harvest Node State Structure

  Each harvest node has:
  - `entity` - Entity struct with position, rotation, guid
  - `node_type_id` - Type of harvestable resource
  - `spawn_position` - Original spawn position
  - `spawn_rotation` - Original spawn rotation
  - `state` - Current state (:available or :depleted)
  - `respawn_timer` - Timer ref for respawn (or nil)
  - `respawn_time_ms` - Time until respawn after gathering

  ## Loot Generation

  Loot is generated from Store data with:
  - Primary drops (always generated)
  - Secondary drops (chance-based)
  - Quantity ranges (min/max per drop)
  """

  alias BezgelorCore.Entity
  alias BezgelorWorld.WorldManager
  alias BezgelorData.Store

  require Logger

  @type node_state :: %{
          entity: Entity.t(),
          node_type_id: non_neg_integer(),
          spawn_position: {float(), float(), float()},
          spawn_rotation: {float(), float(), float()},
          state: :available | :depleted,
          respawn_timer: reference() | nil,
          respawn_time_ms: non_neg_integer()
        }

  @type loot_item :: %{
          item_id: non_neg_integer(),
          name: String.t(),
          quantity: non_neg_integer()
        }

  @doc """
  Load resource spawn data for a world from the data store.

  ## Parameters

  - `world_id` - The world ID to load spawns for

  ## Returns

  List of resource spawn definitions.
  """
  @spec load_resource_spawns(non_neg_integer()) :: [map()]
  def load_resource_spawns(world_id) do
    Store.get_resource_spawns(world_id)
  end

  @doc """
  Create a harvest node from a spawn definition.

  ## Parameters

  - `spawn_def` - The spawn definition map with position, rotation, etc.

  ## Returns

  `{:ok, guid, node_state}` tuple with the new node.
  """
  @spec spawn_from_def(map()) :: {:ok, non_neg_integer(), node_state()}
  def spawn_from_def(spawn_def) do
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    [rx, ry, rz] = spawn_def.rotation
    rotation = {rx, ry, rz}

    guid = WorldManager.generate_guid(:object)

    # Support both node_type_id and harvest_node_id field names
    node_type_id = spawn_def[:node_type_id] || spawn_def[:harvest_node_id] || 0

    # Get node type name for entity name
    node_name = get_node_name(node_type_id)

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
      node_type_id: node_type_id,
      spawn_position: position,
      spawn_rotation: rotation,
      state: :available,
      respawn_timer: nil,
      respawn_time_ms: spawn_def.respawn_time_ms || 60_000
    }

    Logger.debug("Spawned harvest node #{node_name} (#{guid}) at #{inspect(position)}")

    {:ok, guid, node_state}
  end

  @doc """
  Get the display name for a harvest node type.

  ## Parameters

  - `node_type_id` - The node type ID

  ## Returns

  The node name string.
  """
  @spec get_node_name(non_neg_integer()) :: String.t()
  def get_node_name(node_type_id) do
    case Store.get_node_type(node_type_id) do
      {:ok, node_type} -> node_type[:name] || "Harvest Node"
      :error -> "Harvest Node"
    end
  end

  @doc """
  Generate loot from a harvest node.

  ## Parameters

  - `harvest_node_id` - The harvest node type ID

  ## Returns

  List of loot items with item_id, name, and quantity.
  """
  @spec generate_loot(non_neg_integer()) :: [loot_item()]
  def generate_loot(harvest_node_id) do
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

  @doc """
  Roll a drop with quantity range.

  ## Parameters

  - `drop` - Drop definition with item_id, name, min, max

  ## Returns

  List with a single loot item.
  """
  @spec roll_drop(map()) :: [loot_item()]
  def roll_drop(drop) do
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

  @doc """
  Mark a node as depleted after gathering.

  ## Parameters

  - `node_state` - Current node state
  - `respawn_timer` - Timer reference for respawn

  ## Returns

  Updated node state with :depleted status.
  """
  @spec deplete_node(node_state(), reference()) :: node_state()
  def deplete_node(node_state, respawn_timer) do
    %{node_state | state: :depleted, respawn_timer: respawn_timer}
  end

  @doc """
  Mark a node as available after respawn.

  ## Parameters

  - `node_state` - Current node state

  ## Returns

  Updated node state with :available status and cleared timer.
  """
  @spec respawn_node(node_state()) :: node_state()
  def respawn_node(node_state) do
    %{node_state | state: :available, respawn_timer: nil}
  end

  @doc """
  Check if a node is available for gathering.

  ## Parameters

  - `node_state` - Node state to check

  ## Returns

  Boolean indicating availability.
  """
  @spec available?(node_state()) :: boolean()
  def available?(node_state) do
    node_state.state == :available
  end

  @doc """
  Log successful harvest node loading.

  ## Parameters

  - `count` - Number of nodes loaded
  - `world_id` - World ID
  """
  @spec log_load_success(non_neg_integer(), non_neg_integer()) :: :ok
  def log_load_success(count, world_id) do
    Logger.info("Loaded #{count} harvest node spawns for world #{world_id}")
  end

  @doc """
  Log when no resource spawns found.

  ## Parameters

  - `world_id` - World ID
  """
  @spec log_no_spawns(non_neg_integer()) :: :ok
  def log_no_spawns(world_id) do
    Logger.debug("No resource spawns found for world #{world_id}")
  end

  @doc """
  Log node gather event.

  ## Parameters

  - `guid` - Node guid
  - `respawn_time_ms` - Time until respawn
  """
  @spec log_gathered(non_neg_integer(), non_neg_integer()) :: :ok
  def log_gathered(guid, respawn_time_ms) do
    Logger.debug("Node #{guid} gathered, respawning in #{respawn_time_ms}ms")
  end

  # Helper to handle both atom and string keys in maps (from JSON parsing)
  @doc false
  @spec get_map_value(map(), atom(), term()) :: term()
  def get_map_value(map, key, default) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key), default)
      value -> value
    end
  end
end
