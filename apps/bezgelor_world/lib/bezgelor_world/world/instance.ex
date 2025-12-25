defmodule BezgelorWorld.World.Instance do
  @moduledoc """
  World instance GenServer.

  Each instance represents an active shard of a world containing:
  - Entities (players, creatures, objects)
  - Creature state and AI processing
  - World-specific state
  - Spatial index for range queries

  ## Per-Zone Creature Management

  As of the per-zone architecture refactor, creature management is handled
  directly by each World.Instance rather than a global CreatureManager singleton.
  This provides:

  - **Parallel spawn loading**: Each zone loads spawns independently
  - **Per-zone AI processing**: AI ticks process only creatures in each zone
  - **Natural lifecycle**: Creature state tied to zone instance lifecycle
  - **Single source of truth**: No redundant state between managers

  ## Important: world_id vs zone_id

  This module is keyed by `world_id`, NOT `zone_id`. Understanding the distinction
  is critical for correct instance lookup:

  | Concept | Description | Example |
  |---------|-------------|---------|
  | `world_id` | Map/continent ID from WorldLocation2 table | 1634 = Gambler's Ruin |
  | `zone_id` | Sub-region within a world from Zone table | 4844 = Cryo Awakening Protocol |

  A single world can contain multiple zones (e.g., Thayd has several sub-zones),
  but all entities in those zones share the same World.Instance process.

  ### Where to find these IDs

  - `world_id`: `session_data[:world_id]` - set when player enters world
  - `zone_id`: `session_data[:zone_id]` - updated as player moves between zones

  ### Common pitfalls

  - **Don't use zone_id for instance lookup** - use world_id
  - **zone_id changes as player moves** - world_id stays constant while in same map
  - **Dungeons have their own world_id** - not just a zone within an open world

  ## Instance Types

  - **Open World**: Shared instances (e.g., main world zones, cities)
  - **Dungeon**: Private instances per group (unique instance_id per group)
  - **Housing**: Private instances per player/guild
  - **Battleground/Arena**: PvP instances with their own lifecycle

  ## Usage

      # Add a player to the world instance
      World.Instance.add_entity({world_id, instance_id}, player_entity)

      # Find entities in range
      World.Instance.entities_in_range({world_id, instance_id}, {x, y, z}, 100.0)

      # Broadcast to all entities
      World.Instance.broadcast({world_id, instance_id}, {:chat, sender, message})

      # Get creature state (per-zone)
      World.Instance.get_creature({world_id, instance_id}, guid)

      # Damage a creature
      World.Instance.damage_creature({world_id, instance_id}, guid, damage, attacker_guid)
  """

  use GenServer
  import Bitwise

  alias BezgelorCore.{AI, CreatureTemplate, Entity, SpatialGrid}
  alias BezgelorWorld.{CombatBroadcaster, CreatureDeath, TickScheduler, WorldManager}
  alias BezgelorWorld.World.CreatureState
  alias BezgelorData.Store

  require Logger

  @type instance_id :: non_neg_integer()

  @type creature_state :: %{
          entity: Entity.t(),
          template: CreatureTemplate.t(),
          ai: AI.t(),
          spawn_position: {float(), float(), float()},
          respawn_timer: reference() | nil,
          target_position: {float(), float(), float()} | nil,
          world_id: non_neg_integer()
        }

  @type harvest_node_state :: %{
          entity: Entity.t(),
          node_type_id: non_neg_integer(),
          spawn_position: {float(), float(), float()},
          spawn_rotation: {float(), float(), float()},
          state: :available | :depleted,
          respawn_timer: reference() | nil,
          respawn_time_ms: non_neg_integer()
        }

  @type state :: %{
          world_id: non_neg_integer(),
          instance_id: instance_id(),
          world_data: map(),
          entities: %{non_neg_integer() => Entity.t()},
          spatial_grid: SpatialGrid.t(),
          players: MapSet.t(non_neg_integer()),
          creatures: MapSet.t(non_neg_integer()),
          # Per-zone creature management (merged from CreatureManager)
          creature_states: %{non_neg_integer() => creature_state()},
          spawn_definitions: [map()],
          spline_index: map(),
          spawns_loaded: boolean(),
          # Per-zone harvest node management (merged from HarvestNodeManager)
          harvest_nodes: %{non_neg_integer() => harvest_node_state()},
          # Phase 3: Lazy zone activation
          # When lazy_loading is true:
          # - Spawns are deferred until first player enters
          # - Instance stops after idle_timeout_ms when players leave
          lazy_loading: boolean(),
          # Timer ref for idle shutdown (when lazy_loading is true)
          idle_timeout_ref: reference() | nil,
          # Timestamp when last player left (for metrics/debugging)
          last_player_left_at: integer() | nil
        }

  # Idle timeout: 5 minutes with no players before shutdown
  @idle_timeout_ms 5 * 60 * 1000

  # Client API

  @doc """
  Start a world instance.
  """
  def start_link(opts) do
    world_id = Keyword.fetch!(opts, :world_id)
    instance_id = Keyword.fetch!(opts, :instance_id)

    GenServer.start_link(__MODULE__, opts, name: via_tuple(world_id, instance_id))
  end

  @doc """
  Get the registry name for a world instance.
  """
  def via_tuple(world_id, instance_id) do
    {:via, Registry, {BezgelorWorld.WorldRegistry, {world_id, instance_id}}}
  end

  @doc """
  Add an entity to the world.
  """
  @spec add_entity(pid() | {non_neg_integer(), instance_id()}, Entity.t()) :: :ok
  def add_entity(instance, %Entity{} = entity) when is_pid(instance) do
    GenServer.cast(instance, {:add_entity, entity})
  end

  def add_entity({world_id, instance_id}, %Entity{} = entity) do
    GenServer.cast(via_tuple(world_id, instance_id), {:add_entity, entity})
  end

  @doc """
  Remove an entity from the world.
  """
  @spec remove_entity(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) :: :ok
  def remove_entity(instance, guid) when is_pid(instance) do
    GenServer.cast(instance, {:remove_entity, guid})
  end

  def remove_entity({world_id, instance_id}, guid) do
    GenServer.cast(via_tuple(world_id, instance_id), {:remove_entity, guid})
  end

  # Timeout for GenServer calls to prevent deadlocks (10 seconds)
  @call_timeout 10_000

  @doc """
  Get an entity by GUID.
  """
  @spec get_entity(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          {:ok, Entity.t()} | :error
  def get_entity(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_entity, guid}, @call_timeout)
  end

  def get_entity({world_id, instance_id}, guid) do
    GenServer.call(via_tuple(world_id, instance_id), {:get_entity, guid}, @call_timeout)
  end

  @doc """
  Get the creature_id (template ID) for an entity by GUID.

  Returns {:ok, creature_id} if the entity exists and is a creature,
  or :error if not found or not a creature.
  """
  @spec get_entity_creature_id(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          {:ok, non_neg_integer()} | :error
  def get_entity_creature_id(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_entity_creature_id, guid}, @call_timeout)
  end

  def get_entity_creature_id({world_id, instance_id}, guid) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:get_entity_creature_id, guid},
      @call_timeout
    )
  end

  @doc """
  Update an entity's state.
  """
  @spec update_entity(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          (Entity.t() -> Entity.t())
        ) ::
          :ok | :error
  def update_entity(instance, guid, update_fn) when is_pid(instance) do
    GenServer.call(instance, {:update_entity, guid, update_fn}, @call_timeout)
  end

  def update_entity({world_id, instance_id}, guid, update_fn) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:update_entity, guid, update_fn},
      @call_timeout
    )
  end

  @doc """
  Update an entity's position efficiently.

  This is more efficient than update_entity when only the position changes,
  as it avoids the overhead of a full entity update.
  """
  @spec update_entity_position(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          Entity.position()
        ) ::
          :ok | :error
  def update_entity_position(instance, guid, position) when is_pid(instance) do
    GenServer.call(instance, {:update_entity_position, guid, position}, @call_timeout)
  end

  def update_entity_position({world_id, instance_id}, guid, position) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:update_entity_position, guid, position},
      @call_timeout
    )
  end

  @doc """
  Batch update creature entities from ZoneManager.
  This is called asynchronously by ZoneManager after AI tick processing
  to keep World.Instance's entity map in sync for broadcasting.
  """
  @spec update_creature_entities(non_neg_integer(), instance_id(), [{non_neg_integer(), Entity.t()}]) ::
          :ok
  def update_creature_entities(world_id, instance_id, entity_updates) do
    GenServer.cast(
      via_tuple(world_id, instance_id),
      {:update_creature_entities, entity_updates}
    )
  end

  @doc """
  Find entities within range of a position.
  """
  @spec entities_in_range(pid() | {non_neg_integer(), instance_id()}, Entity.position(), float()) ::
          [Entity.t()]
  def entities_in_range(instance, position, radius) when is_pid(instance) do
    GenServer.call(instance, {:entities_in_range, position, radius}, @call_timeout)
  end

  def entities_in_range({world_id, instance_id}, position, radius) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:entities_in_range, position, radius},
      @call_timeout
    )
  end

  @doc """
  Get all players in the world instance.
  """
  @spec list_players(pid() | {non_neg_integer(), instance_id()}) :: [Entity.t()]
  def list_players(instance) when is_pid(instance) do
    GenServer.call(instance, :list_players, @call_timeout)
  end

  def list_players({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :list_players, @call_timeout)
  end

  @doc """
  Get player count in the world instance.
  """
  @spec player_count(pid() | {non_neg_integer(), instance_id()}) :: non_neg_integer()
  def player_count(instance) when is_pid(instance) do
    GenServer.call(instance, :player_count, @call_timeout)
  end

  def player_count({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :player_count, @call_timeout)
  end

  @doc """
  Broadcast a message to all player entities in the world instance.
  """
  @spec broadcast(pid() | {non_neg_integer(), instance_id()}, term()) :: :ok
  def broadcast(instance, message) when is_pid(instance) do
    GenServer.cast(instance, {:broadcast, message})
  end

  def broadcast({world_id, instance_id}, message) do
    GenServer.cast(via_tuple(world_id, instance_id), {:broadcast, message})
  end

  @doc """
  Get world instance info.
  """
  @spec info(pid() | {non_neg_integer(), instance_id()}) :: map()
  def info(instance) when is_pid(instance) do
    GenServer.call(instance, :info, @call_timeout)
  end

  def info({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :info, @call_timeout)
  end

  # =====================================================================
  # Creature Management API (per-zone)
  # =====================================================================

  @doc """
  Get a creature's full state by GUID.
  """
  @spec get_creature(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          creature_state() | nil
  def get_creature(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_creature, guid}, @call_timeout)
  end

  def get_creature({world_id, instance_id}, guid) do
    GenServer.call(via_tuple(world_id, instance_id), {:get_creature, guid}, @call_timeout)
  end

  @doc """
  Get all creatures in this zone.
  """
  @spec list_creatures(pid() | {non_neg_integer(), instance_id()}) :: [creature_state()]
  def list_creatures(instance) when is_pid(instance) do
    GenServer.call(instance, :list_creatures, @call_timeout)
  end

  def list_creatures({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :list_creatures, @call_timeout)
  end

  @doc """
  Get creatures within range of a position in this zone.
  """
  @spec get_creatures_in_range(
          pid() | {non_neg_integer(), instance_id()},
          {float(), float(), float()},
          float()
        ) :: [creature_state()]
  def get_creatures_in_range(instance, position, range) when is_pid(instance) do
    GenServer.call(instance, {:get_creatures_in_range, position, range}, @call_timeout)
  end

  def get_creatures_in_range({world_id, instance_id}, position, range) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:get_creatures_in_range, position, range},
      @call_timeout
    )
  end

  @doc """
  Apply damage to a creature from an attacker.
  """
  @spec damage_creature(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, :damaged | :killed, map()} | {:error, term()}
  def damage_creature(instance, creature_guid, attacker_guid, damage) when is_pid(instance) do
    GenServer.call(
      instance,
      {:damage_creature, creature_guid, attacker_guid, damage},
      @call_timeout
    )
  end

  def damage_creature({world_id, instance_id}, creature_guid, attacker_guid, damage) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:damage_creature, creature_guid, attacker_guid, damage},
      @call_timeout
    )
  end

  @doc """
  Check if a creature is alive and targetable.
  """
  @spec creature_targetable?(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          boolean()
  def creature_targetable?(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:creature_targetable, guid}, @call_timeout)
  end

  def creature_targetable?({world_id, instance_id}, guid) do
    GenServer.call(via_tuple(world_id, instance_id), {:creature_targetable, guid}, @call_timeout)
  end

  @doc """
  Get the count of creatures in this zone.
  """
  @spec creature_count(pid() | {non_neg_integer(), instance_id()}) :: non_neg_integer()
  def creature_count(instance) when is_pid(instance) do
    GenServer.call(instance, :creature_count, @call_timeout)
  end

  def creature_count({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :creature_count, @call_timeout)
  end

  @doc """
  Enter combat for a creature against a target.
  """
  @spec creature_enter_combat(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def creature_enter_combat(instance, creature_guid, target_guid) when is_pid(instance) do
    GenServer.cast(instance, {:creature_enter_combat, creature_guid, target_guid})
  end

  def creature_enter_combat({world_id, instance_id}, creature_guid, target_guid) do
    GenServer.cast(
      via_tuple(world_id, instance_id),
      {:creature_enter_combat, creature_guid, target_guid}
    )
  end

  @doc """
  Set the target position for a creature (used for AI chase calculations).
  """
  @spec set_target_position(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          {float(), float(), float()}
        ) :: :ok
  def set_target_position(instance, creature_guid, position) when is_pid(instance) do
    GenServer.cast(instance, {:set_target_position, creature_guid, position})
  end

  def set_target_position({world_id, instance_id}, creature_guid, position) do
    GenServer.cast(
      via_tuple(world_id, instance_id),
      {:set_target_position, creature_guid, position}
    )
  end

  @doc """
  Spawn a creature from a template at a position.
  """
  @spec spawn_creature(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          {float(), float(), float()}
        ) :: {:ok, non_neg_integer()} | {:error, term()}
  def spawn_creature(instance, template_id, position) when is_pid(instance) do
    GenServer.call(instance, {:spawn_creature, template_id, position}, @call_timeout)
  end

  def spawn_creature({world_id, instance_id}, template_id, position) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:spawn_creature, template_id, position},
      @call_timeout
    )
  end

  # =====================================================================
  # Harvest Node Management API (per-zone)
  # =====================================================================

  @doc """
  Get a harvest node by GUID.
  """
  @spec get_harvest_node(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          harvest_node_state() | nil
  def get_harvest_node(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_harvest_node, guid}, @call_timeout)
  end

  def get_harvest_node({world_id, instance_id}, guid) do
    GenServer.call(via_tuple(world_id, instance_id), {:get_harvest_node, guid}, @call_timeout)
  end

  @doc """
  Get all harvest nodes in this zone.
  """
  @spec list_harvest_nodes(pid() | {non_neg_integer(), instance_id()}) :: [harvest_node_state()]
  def list_harvest_nodes(instance) when is_pid(instance) do
    GenServer.call(instance, :list_harvest_nodes, @call_timeout)
  end

  def list_harvest_nodes({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :list_harvest_nodes, @call_timeout)
  end

  @doc """
  Get the count of harvest nodes in this zone.
  """
  @spec harvest_node_count(pid() | {non_neg_integer(), instance_id()}) :: non_neg_integer()
  def harvest_node_count(instance) when is_pid(instance) do
    GenServer.call(instance, :harvest_node_count, @call_timeout)
  end

  def harvest_node_count({world_id, instance_id}) do
    GenServer.call(via_tuple(world_id, instance_id), :harvest_node_count, @call_timeout)
  end

  @doc """
  Gather from a harvest node. Returns loot and marks node as depleted.
  """
  @spec gather_harvest_node(
          pid() | {non_neg_integer(), instance_id()},
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, [map()]} | {:error, :not_found | :depleted}
  def gather_harvest_node(instance, node_guid, gatherer_guid) when is_pid(instance) do
    GenServer.call(instance, {:gather_harvest_node, node_guid, gatherer_guid}, @call_timeout)
  end

  def gather_harvest_node({world_id, instance_id}, node_guid, gatherer_guid) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:gather_harvest_node, node_guid, gatherer_guid},
      @call_timeout
    )
  end

  @doc """
  Check if a harvest node is available for gathering.
  """
  @spec harvest_node_available?(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          boolean()
  def harvest_node_available?(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:harvest_node_available, guid}, @call_timeout)
  end

  def harvest_node_available?({world_id, instance_id}, guid) do
    GenServer.call(
      via_tuple(world_id, instance_id),
      {:harvest_node_available, guid},
      @call_timeout
    )
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    world_id = Keyword.fetch!(opts, :world_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    world_data = Keyword.get(opts, :world_data, %{})
    lazy_loading = Keyword.get(opts, :lazy_loading, false)

    # Build spline index for this zone (for patrol path matching)
    # This is a subset of the global index filtered for this world
    spline_index = build_zone_spline_index(world_id)

    state = %{
      world_id: world_id,
      instance_id: instance_id,
      world_data: world_data,
      entities: %{},
      spatial_grid: SpatialGrid.new(50.0),
      players: MapSet.new(),
      creatures: MapSet.new(),
      # Per-zone creature management
      creature_states: %{},
      spawn_definitions: [],
      spline_index: spline_index,
      spawns_loaded: false,
      # Per-zone harvest node management
      harvest_nodes: %{},
      # Phase 3: Lazy zone activation
      lazy_loading: lazy_loading,
      idle_timeout_ref: nil,
      last_player_left_at: nil
    }

    # Register with TickScheduler for AI processing
    try do
      TickScheduler.register_listener(self())
    catch
      :exit, _ -> :ok
    end

    Logger.info(
      "World instance started: #{world_data[:name] || world_id} (instance #{instance_id})#{if lazy_loading, do: " [spawns deferred]", else: ""}"
    )

    # Load creature spawns asynchronously after init completes
    # (unless lazy loading is enabled - then defer until first player enters)
    if lazy_loading do
      {:ok, state}
    else
      {:ok, state, {:continue, :load_spawns}}
    end
  end

  @impl true
  def handle_continue(:load_spawns, state) do
    # Load creature spawns directly into this instance's state
    # Each zone loads its own spawns in parallel (natural parallelism)
    world_id = state.world_id

    state =
      case Store.get_creature_spawns(world_id) do
        {:ok, zone_data} ->
          {spawned_count, new_state} =
            spawn_from_definitions(zone_data.creature_spawns, state)

          Logger.info("Loaded #{spawned_count} creature spawns for world #{world_id}")
          %{new_state | spawns_loaded: true}

        :error ->
          Logger.debug("No spawn data found for world #{world_id}")
          %{state | spawns_loaded: true}
      end

    # Load harvest nodes (per-zone management)
    state = load_harvest_nodes(state)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_entity, entity}, state) do
    entities = Map.put(state.entities, entity.guid, entity)
    spatial_grid = SpatialGrid.insert(state.spatial_grid, entity.guid, entity.position)

    # Track by type
    state =
      case entity.type do
        :player ->
          # Cancel any pending idle timeout when a player enters
          state = cancel_idle_timeout(state)

          %{
            state
            | entities: entities,
              spatial_grid: spatial_grid,
              players: MapSet.put(state.players, entity.guid),
              last_player_left_at: nil
          }

        :creature ->
          %{
            state
            | entities: entities,
              spatial_grid: spatial_grid,
              creatures: MapSet.put(state.creatures, entity.guid)
          }

        _ ->
          %{state | entities: entities, spatial_grid: spatial_grid}
      end

    # If lazy loading is enabled and this is the first player, trigger spawn loading
    state =
      if entity.type == :player and state.lazy_loading and not state.spawns_loaded do
        load_spawns_sync(state)
      else
        state
      end

    Logger.debug("Entity #{entity.guid} (#{entity.type}) added to world #{state.world_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_entity, guid}, state) do
    entity = Map.get(state.entities, guid)
    entities = Map.delete(state.entities, guid)
    spatial_grid = SpatialGrid.remove(state.spatial_grid, guid)

    state =
      if entity do
        case entity.type do
          :player ->
            new_players = MapSet.delete(state.players, guid)

            state = %{
              state
              | entities: entities,
                spatial_grid: spatial_grid,
                players: new_players
            }

            # Start idle timeout if this was the last player
            if MapSet.size(new_players) == 0 and state.lazy_loading do
              start_idle_timeout(state)
            else
              state
            end

          :creature ->
            %{
              state
              | entities: entities,
                spatial_grid: spatial_grid,
                creatures: MapSet.delete(state.creatures, guid)
            }

          _ ->
            %{state | entities: entities, spatial_grid: spatial_grid}
        end
      else
        %{state | entities: entities, spatial_grid: spatial_grid}
      end

    Logger.debug("Entity #{guid} removed from world #{state.world_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    # Broadcast to all player connection processes in this world instance
    sessions =
      BezgelorWorld.WorldManager.get_zone_instance_sessions(state.world_id, state.instance_id)

    case message do
      # Packet broadcast: {opcode, packet_data}
      {opcode, packet_data} when is_atom(opcode) and is_binary(packet_data) ->
        Enum.each(sessions, fn session ->
          BezgelorWorld.WorldManager.send_packet(session.connection_pid, opcode, packet_data)
        end)

      # Packet broadcast with exclusion: {opcode, packet_data, exclude_guid}
      {opcode, packet_data, exclude_guid} when is_atom(opcode) and is_binary(packet_data) ->
        Enum.each(sessions, fn session ->
          if session.entity_guid != exclude_guid do
            BezgelorWorld.WorldManager.send_packet(session.connection_pid, opcode, packet_data)
          end
        end)

      # Legacy/debug message format
      _ ->
        Logger.debug(
          "World #{state.world_id} broadcast: #{inspect(message)} to #{length(sessions)} players"
        )
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:creature_enter_combat, creature_guid, target_guid}, state) do
    state =
      case Map.get(state.creature_states, creature_guid) do
        nil ->
          state

        %{ai: ai} when ai.state == :dead ->
          state

        creature_state ->
          # Enter combat
          ai = AI.enter_combat(creature_state.ai, target_guid)
          new_creature_state = %{creature_state | ai: ai}

          # Trigger social aggro for nearby same-faction creatures
          state = trigger_social_aggro(creature_state, target_guid, state)

          %{
            state
            | creature_states: Map.put(state.creature_states, creature_guid, new_creature_state)
          }
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_target_position, creature_guid, position}, state) do
    state =
      case Map.get(state.creature_states, creature_guid) do
        nil ->
          state

        creature_state ->
          new_creature_state = %{creature_state | target_position: position}

          %{
            state
            | creature_states: Map.put(state.creature_states, creature_guid, new_creature_state)
          }
      end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:get_entity, guid}, _from, state) do
    result =
      case Map.get(state.entities, guid) do
        nil -> :error
        entity -> {:ok, entity}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_entity_creature_id, guid}, _from, state) do
    result =
      case Map.get(state.entities, guid) do
        nil ->
          :error

        %{type: :creature, creature_id: creature_id} when not is_nil(creature_id) ->
          {:ok, creature_id}

        _ ->
          :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_entity, guid, update_fn}, _from, state) do
    case Map.get(state.entities, guid) do
      nil ->
        {:reply, :error, state}

      entity ->
        updated_entity = update_fn.(entity)
        entities = Map.put(state.entities, guid, updated_entity)

        # Update spatial grid if position changed
        spatial_grid =
          if entity.position != updated_entity.position do
            SpatialGrid.update(state.spatial_grid, guid, updated_entity.position)
          else
            state.spatial_grid
          end

        {:reply, :ok, %{state | entities: entities, spatial_grid: spatial_grid}}
    end
  end

  @impl true
  def handle_call({:update_entity_position, guid, new_position}, _from, state) do
    case Map.get(state.entities, guid) do
      nil ->
        {:reply, :error, state}

      entity ->
        updated_entity = %{entity | position: new_position}
        entities = Map.put(state.entities, guid, updated_entity)
        spatial_grid = SpatialGrid.update(state.spatial_grid, guid, new_position)
        {:reply, :ok, %{state | entities: entities, spatial_grid: spatial_grid}}
    end
  end

  @impl true
  def handle_call({:entities_in_range, position, radius}, _from, state) do
    # Use spatial grid for O(k) lookup instead of O(n) iteration
    guids = SpatialGrid.entities_in_range(state.spatial_grid, position, radius)

    entities =
      guids
      |> Enum.map(&Map.get(state.entities, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, entities, state}
  end

  @impl true
  def handle_call(:list_players, _from, state) do
    players =
      state.players
      |> MapSet.to_list()
      |> Enum.map(&Map.get(state.entities, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, players, state}
  end

  @impl true
  def handle_call(:player_count, _from, state) do
    {:reply, MapSet.size(state.players), state}
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      world_id: state.world_id,
      instance_id: state.instance_id,
      world_name: Map.get(state.world_data, :name, "Unknown"),
      player_count: MapSet.size(state.players),
      creature_count: MapSet.size(state.creatures),
      total_entities: map_size(state.entities)
    }

    {:reply, info, state}
  end

  # =====================================================================
  # Creature Management Callbacks
  # =====================================================================

  @impl true
  def handle_call({:get_creature, guid}, _from, state) do
    {:reply, Map.get(state.creature_states, guid), state}
  end

  @impl true
  def handle_call(:list_creatures, _from, state) do
    {:reply, Map.values(state.creature_states), state}
  end

  @impl true
  def handle_call({:get_creatures_in_range, position, range}, _from, state) do
    creatures =
      state.creature_states
      |> Map.values()
      |> Enum.filter(fn %{entity: entity, ai: ai} ->
        not AI.dead?(ai) and AI.distance(entity.position, position) <= range
      end)

    {:reply, creatures, state}
  end

  @impl true
  def handle_call({:damage_creature, creature_guid, attacker_guid, damage}, _from, state) do
    case Map.get(state.creature_states, creature_guid) do
      nil ->
        {:reply, {:error, :creature_not_found}, state}

      %{ai: ai} when ai.state == :dead ->
        {:reply, {:error, :creature_dead}, state}

      creature_state ->
        {result, new_creature_state, state} =
          apply_damage_to_creature(creature_state, attacker_guid, damage, state)

        creature_states = Map.put(state.creature_states, creature_guid, new_creature_state)
        {:reply, result, %{state | creature_states: creature_states}}
    end
  end

  @impl true
  def handle_call({:creature_targetable, guid}, _from, state) do
    result =
      case Map.get(state.creature_states, guid) do
        nil -> false
        %{ai: ai} -> AI.targetable?(ai)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:creature_count, _from, state) do
    {:reply, map_size(state.creature_states), state}
  end

  @impl true
  def handle_call({:spawn_creature, template_id, position}, _from, state) do
    case CreatureTemplate.get(template_id) do
      nil ->
        {:reply, {:error, :template_not_found}, state}

      template ->
        guid = WorldManager.generate_guid(:creature)

        entity = %Entity{
          guid: guid,
          type: :creature,
          name: template.name,
          display_info: template.display_info,
          faction: CreatureState.faction_to_int(template.faction),
          level: template.level,
          position: position,
          creature_id: template_id,
          health: template.max_health,
          max_health: template.max_health
        }

        ai = AI.new(position)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          target_position: nil,
          world_id: state.world_id
        }

        # Add to entities and creature_states
        entities = Map.put(state.entities, guid, entity)
        spatial_grid = SpatialGrid.insert(state.spatial_grid, guid, position)
        creatures = MapSet.put(state.creatures, guid)
        creature_states = Map.put(state.creature_states, guid, creature_state)

        state = %{
          state
          | entities: entities,
            spatial_grid: spatial_grid,
            creatures: creatures,
            creature_states: creature_states
        }

        Logger.debug("Spawned creature #{template.name} (#{guid}) at #{inspect(position)}")
        {:reply, {:ok, guid}, state}
    end
  end

  # =====================================================================
  # Harvest Node Management Callbacks
  # =====================================================================

  @impl true
  def handle_call({:get_harvest_node, guid}, _from, state) do
    {:reply, Map.get(state.harvest_nodes, guid), state}
  end

  @impl true
  def handle_call(:list_harvest_nodes, _from, state) do
    {:reply, Map.values(state.harvest_nodes), state}
  end

  @impl true
  def handle_call(:harvest_node_count, _from, state) do
    {:reply, map_size(state.harvest_nodes), state}
  end

  @impl true
  def handle_call({:gather_harvest_node, node_guid, gatherer_guid}, _from, state) do
    case Map.get(state.harvest_nodes, node_guid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{state: :depleted} ->
        {:reply, {:error, :depleted}, state}

      node_state ->
        {result, new_node_state, new_state} =
          do_gather_harvest_node(node_state, gatherer_guid, state)

        harvest_nodes = Map.put(state.harvest_nodes, node_guid, new_node_state)
        {:reply, result, %{new_state | harvest_nodes: harvest_nodes}}
    end
  end

  @impl true
  def handle_call({:harvest_node_available, guid}, _from, state) do
    result =
      case Map.get(state.harvest_nodes, guid) do
        nil -> false
        %{state: :available} -> true
        _ -> false
      end

    {:reply, result, state}
  end

  # Handle batch entity updates from ZoneManager (async)
  @impl true
  def handle_cast({:update_creature_entities, entity_updates}, state) do
    # Update entities map with new creature positions/health
    entities =
      Enum.reduce(entity_updates, state.entities, fn {guid, entity}, entities ->
        Map.put(entities, guid, entity)
      end)

    {:noreply, %{state | entities: entities}}
  end

  # Tick processing - creature AI is now handled by ZoneManager
  # This handler remains for future non-creature tick processing
  @impl true
  def handle_info({:tick, _tick_number}, state) do
    # Creature AI ticks are handled by ZoneManager
    # Entity updates are pushed back via handle_cast({:update_creature_entities, ...})
    {:noreply, state}
  end

  @impl true
  def handle_info({:respawn_creature, guid}, state) do
    state =
      case Map.get(state.creature_states, guid) do
        nil ->
          state

        creature_state ->
          # Respawn the creature
          new_entity = %{
            creature_state.entity
            | health: creature_state.template.max_health,
              position: creature_state.spawn_position
          }

          new_ai = AI.respawn(creature_state.ai)

          new_creature_state = %{
            creature_state
            | entity: new_entity,
              ai: new_ai,
              respawn_timer: nil
          }

          # Update entities map too
          entities = Map.put(state.entities, guid, new_entity)
          spatial_grid = SpatialGrid.update(state.spatial_grid, guid, new_entity.position)

          Logger.debug("Respawned creature #{new_entity.name} (#{guid})")

          %{
            state
            | creature_states: Map.put(state.creature_states, guid, new_creature_state),
              entities: entities,
              spatial_grid: spatial_grid
          }
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:respawn_harvest_node, guid}, state) do
    state =
      case Map.get(state.harvest_nodes, guid) do
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
          %{state | harvest_nodes: Map.put(state.harvest_nodes, guid, new_node_state)}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    # Only stop if still no players (they may have re-entered)
    if MapSet.size(state.players) == 0 do
      Logger.info(
        "World instance #{state.world_id} idle timeout - stopping (lazy loading enabled)"
      )

      # Unregister from tick scheduler before stopping
      try do
        TickScheduler.unregister_listener(self())
      catch
        :exit, _ -> :ok
      end

      {:stop, :normal, state}
    else
      # Players re-entered, cancel the timeout
      {:noreply, %{state | idle_timeout_ref: nil, last_player_left_at: nil}}
    end
  end

  # =====================================================================
  # Private Functions - Creature Management
  # =====================================================================

  # Build zone-specific spline index
  # Returns a map with world_id key for compatibility with Store.find_nearest_spline_indexed
  defp build_zone_spline_index(world_id) do
    try do
      global_index = Store.build_spline_spatial_index()
      # Keep as map keyed by world_id for compatibility with find_nearest_spline_indexed
      splines = Map.get(global_index, world_id, [])
      %{world_id => splines}
    rescue
      _ -> %{}
    end
  end

  # =====================================================================
  # Private Functions - Lazy Zone Activation (Phase 3)
  # =====================================================================

  # Cancel any pending idle timeout timer
  defp cancel_idle_timeout(%{idle_timeout_ref: nil} = state), do: state

  defp cancel_idle_timeout(%{idle_timeout_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | idle_timeout_ref: nil}
  end

  # Start idle timeout timer when last player leaves
  defp start_idle_timeout(state) do
    now = System.monotonic_time(:millisecond)
    ref = Process.send_after(self(), :idle_timeout, @idle_timeout_ms)

    Logger.debug(
      "World instance #{state.world_id} starting idle timeout (#{div(@idle_timeout_ms, 1000)}s)"
    )

    %{state | idle_timeout_ref: ref, last_player_left_at: now}
  end

  # Load spawns synchronously (for lazy loading when first player enters)
  defp load_spawns_sync(state) do
    world_id = state.world_id
    zone_name = state.world_data[:name] || world_id

    state =
      case Store.get_creature_spawns(world_id) do
        {:ok, zone_data} ->
          {spawned_count, new_state} =
            spawn_from_definitions(zone_data.creature_spawns, state)

          Logger.info("Loaded #{spawned_count} creature spawns for #{zone_name} (first player entered)")
          %{new_state | spawns_loaded: true}

        :error ->
          Logger.debug("No spawn data found for #{zone_name}")
          %{state | spawns_loaded: true}
      end

    # Also load harvest nodes
    load_harvest_nodes(state)
  end

  # Spawn creatures from static data definitions
  defp spawn_from_definitions(spawn_defs, state) do
    # Store definitions for reference
    state = %{state | spawn_definitions: state.spawn_definitions ++ spawn_defs}

    world_id = state.world_id
    spline_index = state.spline_index

    # Spawn each creature
    {spawned_count, state} =
      Enum.reduce(spawn_defs, {0, state}, fn spawn_def, {count, state} ->
        case spawn_creature_from_def(spawn_def, world_id, spline_index) do
          {:ok, guid, creature_state} ->
            # Add entity to entities map
            entity = creature_state.entity
            entities = Map.put(state.entities, guid, entity)
            spatial_grid = SpatialGrid.insert(state.spatial_grid, guid, entity.position)
            creatures = MapSet.put(state.creatures, guid)
            creature_states = Map.put(state.creature_states, guid, creature_state)

            state = %{
              state
              | entities: entities,
                spatial_grid: spatial_grid,
                creatures: creatures,
                creature_states: creature_states
            }

            {count + 1, state}

          {:error, reason} ->
            Logger.warning(
              "Failed to spawn creature #{spawn_def.creature_id} at #{inspect(spawn_def.position)}: #{inspect(reason)}"
            )

            {count, state}
        end
      end)

    {spawned_count, state}
  end

  # Spawn a single creature from a spawn definition
  # Delegates to CreatureState for the actual creation logic
  defp spawn_creature_from_def(spawn_def, world_id, spline_index) do
    CreatureState.build_from_spawn_def(spawn_def, world_id, spline_index)
  end

  # =====================================================================
  # Creature State Helpers (delegates to CreatureState module)
  # =====================================================================

  # Apply damage to a creature - delegates to CreatureState
  defp apply_damage_to_creature(creature_state, attacker_guid, damage, state) do
    killer_level = get_killer_level(attacker_guid, creature_state.template.level, state)

    case CreatureState.apply_damage(creature_state, attacker_guid, damage, killer_level: killer_level) do
      {:ok, :damaged, result_info, new_creature_state} ->
        {{:ok, :damaged, result_info}, new_creature_state, state}

      {:ok, :killed, result_info, new_creature_state} ->
        {{:ok, :killed, result_info}, new_creature_state, state}
    end
  end

  defp get_killer_level(killer_guid, default_level, state) do
    if CreatureDeath.is_player_guid?(killer_guid) do
      case Map.get(state.entities, killer_guid) do
        nil -> default_level
        player_entity -> player_entity.level
      end
    else
      default_level
    end
  end

  # Trigger social aggro for nearby creatures of the same faction
  defp trigger_social_aggro(aggressor_state, target_guid, state) do
    aggressor_faction = aggressor_state.template.faction
    aggressor_pos = aggressor_state.entity.position
    social_range = CreatureTemplate.social_aggro_range(aggressor_state.template)

    state.creature_states
    |> Enum.filter(fn {guid, cs} ->
      guid != aggressor_state.entity.guid and
        cs.template.faction == aggressor_faction and
        cs.ai.state == :idle and
        AI.distance(aggressor_pos, cs.entity.position) <= social_range
    end)
    |> Enum.reduce(state, fn {guid, cs}, acc_state ->
      new_ai = AI.social_aggro(cs.ai, target_guid)
      new_cs = %{cs | ai: new_ai}
      %{acc_state | creature_states: Map.put(acc_state.creature_states, guid, new_cs)}
    end)
  end

  defp apply_creature_attack(creature_entity, template, target_guid, state) do
    if CreatureDeath.is_player_guid?(target_guid) do
      base_damage = CreatureTemplate.roll_damage(template)
      final_damage = apply_damage_mitigation(target_guid, base_damage, state)

      case Map.get(state.entities, target_guid) do
        nil ->
          :ok

        player_entity ->
          updated_entity = Entity.apply_damage(player_entity, final_damage)
          send_creature_attack_effect(creature_entity.guid, target_guid, final_damage)

          if Entity.dead?(updated_entity) do
            handle_player_death(updated_entity, creature_entity.guid)
          end
      end
    end

    :ok
  end

  defp apply_damage_mitigation(player_guid, base_damage, state) do
    target_stats = get_target_defensive_stats(player_guid, state)
    armor = Map.get(target_stats, :armor, 0.0)
    mitigation = min(armor, 0.75)
    final_damage = round(base_damage * (1 - mitigation))
    max(final_damage, 1)
  end

  defp get_target_defensive_stats(player_guid, _state) do
    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        %{armor: 0.0}

      session ->
        character = session[:character]

        if character do
          BezgelorCore.CharacterStats.compute_combat_stats(%{
            level: character.level || 1,
            class: character.class || 1,
            race: character.race || 0
          })
        else
          %{armor: 0.0}
        end
    end
  end

  defp send_creature_attack_effect(creature_guid, player_guid, damage) do
    effect = %{type: :damage, amount: damage, is_crit: false}
    CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])
  end

  defp handle_player_death(player_entity, killer_guid) do
    Logger.info(
      "Player #{player_entity.name} (#{player_entity.guid}) killed by creature #{killer_guid}"
    )

    CombatBroadcaster.broadcast_entity_death(player_entity.guid, killer_guid, [player_entity.guid])

    :ok
  end

  # Broadcast creature movement to players in the zone
  defp broadcast_creature_movement(creature_guid, path, speed, world_id, instance_id)
       when length(path) > 1 do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand
    alias BezgelorProtocol.PacketWriter

    state_command = %{type: :set_state, state: 0x02}
    move_defaults = %{type: :set_move_defaults, blend: false}
    rotation_defaults = %{type: :set_rotation_defaults, blend: false}

    path_command = %{
      type: :set_position_path,
      positions: path,
      speed: speed,
      spline_type: :linear,
      spline_mode: :one_shot,
      offset: 0,
      blend: true
    }

    packet = %ServerEntityCommand{
      guid: creature_guid,
      time: System.system_time(:millisecond) |> band(0xFFFFFFFF),
      time_reset: false,
      server_controlled: true,
      commands: [state_command, move_defaults, rotation_defaults, path_command]
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCommand.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    __MODULE__.broadcast({world_id, instance_id}, {:server_entity_command, packet_data})
  end

  defp broadcast_creature_movement(_creature_guid, _path, _speed, _world_id, _instance_id), do: :ok

  defp broadcast_creature_stop(creature_guid, world_id, instance_id) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand
    alias BezgelorProtocol.PacketWriter

    state_command = %{type: :set_state, state: 0x00}
    move_defaults = %{type: :set_move_defaults, blend: false}

    packet = %ServerEntityCommand{
      guid: creature_guid,
      time: System.monotonic_time(:millisecond) |> rem(0xFFFFFFFF),
      time_reset: false,
      server_controlled: true,
      commands: [state_command, move_defaults]
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCommand.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    __MODULE__.broadcast({world_id, instance_id}, {:server_entity_command, packet_data})
  end

  # =====================================================================
  # Private Functions - Harvest Node Management
  # =====================================================================

  # Load harvest nodes from static data
  defp load_harvest_nodes(state) do
    world_id = state.world_id
    resource_spawns = Store.get_resource_spawns(world_id)

    if Enum.empty?(resource_spawns) do
      Logger.debug("No resource spawns found for world #{world_id}")
      state
    else
      {spawned_count, new_state} = spawn_harvest_nodes_from_definitions(resource_spawns, state)
      Logger.info("Loaded #{spawned_count} harvest node spawns for world #{world_id}")
      new_state
    end
  end

  # Spawn harvest nodes from static data definitions
  defp spawn_harvest_nodes_from_definitions(spawn_defs, state) do
    {spawned_count, harvest_nodes} =
      Enum.reduce(spawn_defs, {0, state.harvest_nodes}, fn spawn_def, {count, nodes} ->
        {:ok, guid, node_state} = spawn_harvest_node_from_def(spawn_def)
        {count + 1, Map.put(nodes, guid, node_state)}
      end)

    {spawned_count, %{state | harvest_nodes: harvest_nodes}}
  end

  # Spawn a single harvest node from a spawn definition
  defp spawn_harvest_node_from_def(spawn_def) do
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    [rx, ry, rz] = spawn_def.rotation
    rotation = {rx, ry, rz}

    guid = WorldManager.generate_guid(:object)

    # Support both node_type_id and harvest_node_id field names
    node_type_id = spawn_def[:node_type_id] || spawn_def[:harvest_node_id] || 0

    # Get node type name for entity name
    node_name =
      case Store.get_node_type(node_type_id) do
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

  # Gather from a harvest node (deplete it, generate loot, schedule respawn)
  defp do_gather_harvest_node(node_state, _gatherer_guid, state) do
    # Get node type info for loot generation
    node_type_id = node_state.node_type_id
    loot = generate_harvest_node_loot(node_type_id)

    # Schedule respawn
    respawn_timer =
      Process.send_after(
        self(),
        {:respawn_harvest_node, node_state.entity.guid},
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

  # Generate loot from a harvest node
  defp generate_harvest_node_loot(harvest_node_id) do
    case Store.get_harvest_loot(harvest_node_id) do
      {:ok, loot_data} ->
        loot = get_harvest_map_value(loot_data, :loot, %{})
        primary = get_harvest_map_value(loot, :primary, [])
        secondary = get_harvest_map_value(loot, :secondary, [])

        # Always generate primary drops
        primary_loot =
          Enum.flat_map(primary, fn drop ->
            roll_harvest_drop(drop)
          end)

        # Roll for secondary drops (chance-based)
        secondary_loot =
          Enum.flat_map(secondary, fn drop ->
            chance = get_harvest_map_value(drop, :chance, 0.0)

            if :rand.uniform() <= chance do
              roll_harvest_drop(drop)
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
  defp roll_harvest_drop(drop) do
    item_id = get_harvest_map_value(drop, :item_id, 0)
    name = get_harvest_map_value(drop, :name, "Unknown")
    min_qty = get_harvest_map_value(drop, :min, 1)
    max_qty = get_harvest_map_value(drop, :max, 1)

    quantity =
      if max_qty > min_qty do
        Enum.random(min_qty..max_qty)
      else
        min_qty
      end

    [%{item_id: item_id, name: name, quantity: quantity}]
  end

  # Helper to handle both atom and string keys in maps (from JSON parsing)
  defp get_harvest_map_value(map, key, default) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key), default)
      value -> value
    end
  end
end
