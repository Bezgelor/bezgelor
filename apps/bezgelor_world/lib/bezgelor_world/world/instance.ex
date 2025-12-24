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

  alias BezgelorCore.{AI, CreatureTemplate, Entity, Movement, SpatialGrid}
  alias BezgelorWorld.{CombatBroadcaster, CreatureDeath, HarvestNodeManager, TickScheduler, WorldManager}
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
          spawns_loaded: boolean()
        }

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
    GenServer.call(instance, {:damage_creature, creature_guid, attacker_guid, damage}, @call_timeout)
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

  # Server Callbacks

  @impl true
  def init(opts) do
    world_id = Keyword.fetch!(opts, :world_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    world_data = Keyword.get(opts, :world_data, %{})

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
      spawns_loaded: false
    }

    # Register with TickScheduler for AI processing
    try do
      TickScheduler.register_listener(self())
    catch
      :exit, _ -> :ok
    end

    Logger.info("World instance started: #{world_data[:name] || world_id} (instance #{instance_id})")

    # Load creature spawns asynchronously after init completes
    {:ok, state, {:continue, :load_spawns}}
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

    # Load harvest nodes (still uses HarvestNodeManager for now)
    Task.start(fn ->
      try do
        case HarvestNodeManager.load_zone_spawns(world_id) do
          {:ok, count} ->
            Logger.info("Loaded #{count} harvest node spawns for world #{world_id}")

          {:error, _reason} ->
            :ok
        end
      catch
        kind, reason ->
          Logger.warning(
            "Harvest node loading failed for world #{world_id}: #{inspect(kind)} #{inspect(reason)}"
          )
      end
    end)

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
          %{
            state
            | entities: entities,
              spatial_grid: spatial_grid,
              players: MapSet.put(state.players, entity.guid)
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
            %{
              state
              | entities: entities,
                spatial_grid: spatial_grid,
                players: MapSet.delete(state.players, guid)
            }

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
          faction: faction_to_int(template.faction),
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

          %{state | creature_states: Map.put(state.creature_states, creature_guid, new_creature_state)}
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
          %{state | creature_states: Map.put(state.creature_states, creature_guid, new_creature_state)}
      end

    {:noreply, state}
  end

  # AI Tick processing
  @impl true
  def handle_info({:tick, _tick_number}, state) do
    # Skip AI processing if no players in zone
    if MapSet.size(state.players) == 0 do
      {:noreply, state}
    else
      state = process_ai_tick(state)
      {:noreply, state}
    end
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
  defp spawn_creature_from_def(spawn_def, world_id, spline_index) do
    creature_id = spawn_def.creature_id
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    case get_creature_template(creature_id, spawn_def) do
      {:error, reason} ->
        {:error, reason}

      {:ok, template, display_info, outfit_info} ->
        guid = WorldManager.generate_guid(:creature)

        entity = %Entity{
          guid: guid,
          type: :creature,
          name: template.name,
          display_info: display_info,
          outfit_info: outfit_info,
          faction: spawn_def[:faction1] || faction_to_int(template.faction),
          level: template.level,
          position: position,
          creature_id: creature_id,
          health: template.max_health,
          max_health: template.max_health
        }

        # Build AI options, including patrol path if specified
        ai_opts = build_ai_options(spawn_def, world_id, position, spline_index)
        ai = AI.new(position, ai_opts)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          spawn_def: spawn_def,
          world_id: world_id,
          target_position: nil
        }

        {:ok, guid, creature_state}
    end
  end

  # Get creature template
  defp get_creature_template(creature_id, spawn_def) do
    case CreatureTemplate.get(creature_id) do
      nil ->
        # Fall back to BezgelorData
        case BezgelorData.get_creature(creature_id) do
          {:ok, creature_data} ->
            build_template_from_data(creature_id, creature_data, spawn_def)

          :error ->
            {:error, :template_not_found}
        end

      template ->
        display_info =
          if spawn_def[:display_info] && spawn_def.display_info > 0 do
            spawn_def.display_info
          else
            template.display_info
          end

        outfit_info = spawn_def[:outfit_info] || 0
        {:ok, template, display_info, outfit_info}
    end
  end

  # Build a CreatureTemplate from BezgelorData creature
  defp build_template_from_data(creature_id, creature_data, spawn_def) do
    name = get_creature_name(creature_data)
    tier_id = Map.get(creature_data, :tier_id, 1)
    difficulty_id = Map.get(creature_data, :difficulty_id, 1)
    level = tier_to_level(tier_id)
    max_health = calculate_max_health(tier_id, difficulty_id, level)
    {damage_min, damage_max} = calculate_damage(level, difficulty_id)
    ai_type = archetype_to_ai_type(Map.get(creature_data, :archetype_id, 0))

    template = %CreatureTemplate{
      id: creature_id,
      name: name,
      level: level,
      max_health: max_health,
      faction: :hostile,
      display_info: Map.get(creature_data, :display_group_id, 0),
      ai_type: ai_type,
      aggro_range: if(ai_type == :aggressive, do: 15.0, else: 0.0),
      leash_range: 40.0,
      respawn_time: 60_000,
      xp_reward: level * 10,
      loot_table_id: nil,
      damage_min: damage_min,
      damage_max: damage_max,
      attack_speed: 2000
    }

    display_info =
      if spawn_def[:display_info] && spawn_def.display_info > 0 do
        spawn_def.display_info
      else
        template.display_info
      end

    outfit_info =
      if spawn_def[:outfit_info] && spawn_def.outfit_info > 0 do
        spawn_def.outfit_info
      else
        Map.get(creature_data, :outfit_group_id, 0)
      end

    {:ok, template, display_info, outfit_info}
  end

  defp get_creature_name(creature_data) do
    name_text_id = Map.get(creature_data, :name_text_id, 0)

    case BezgelorData.get_text(name_text_id) do
      {:ok, text} -> text
      :error -> "Creature #{Map.get(creature_data, :id, 0)}"
    end
  end

  defp tier_to_level(tier_id) do
    case tier_id do
      1 -> Enum.random(1..10)
      2 -> Enum.random(10..20)
      3 -> Enum.random(20..35)
      4 -> Enum.random(35..50)
      _ -> Enum.random(1..50)
    end
  end

  defp calculate_max_health(tier_id, difficulty_id, level) do
    base_health = 50 + level * 20

    tier_mult =
      case tier_id do
        1 -> 1.0
        2 -> 1.5
        3 -> 2.0
        4 -> 3.0
        _ -> 1.0
      end

    difficulty_mult =
      case difficulty_id do
        1 -> 1.0
        2 -> 2.0
        3 -> 5.0
        4 -> 10.0
        _ -> 1.0
      end

    round(base_health * tier_mult * difficulty_mult)
  end

  defp calculate_damage(level, difficulty_id) do
    base_min = 5 + level
    base_max = 10 + level * 2

    mult =
      case difficulty_id do
        1 -> 1.0
        2 -> 1.5
        3 -> 2.0
        4 -> 3.0
        _ -> 1.0
      end

    {round(base_min * mult), round(base_max * mult)}
  end

  defp archetype_to_ai_type(archetype_id) do
    case archetype_id do
      30 -> :passive
      31 -> :defensive
      _ -> :aggressive
    end
  end

  defp faction_to_int(:hostile), do: 0
  defp faction_to_int(:neutral), do: 1
  defp faction_to_int(:friendly), do: 2
  defp faction_to_int(_), do: 0

  # Build AI options from spawn definition
  defp build_ai_options(spawn_def, world_id, position, spline_index) do
    waypoints = Map.get(spawn_def, :patrol_waypoints)

    cond do
      is_list(waypoints) and length(waypoints) > 1 ->
        [
          patrol_waypoints: waypoints,
          patrol_speed: Map.get(spawn_def, :patrol_speed, 3.0),
          patrol_mode: Map.get(spawn_def, :patrol_mode, :cyclic)
        ]

      spline_id = Map.get(spawn_def, :spline_id) ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: Map.get(spawn_def, :spline_speed, patrol_data.speed),
              patrol_mode: Map.get(spawn_def, :spline_mode, patrol_data.mode)
            ]

          :error ->
            []
        end

      path_name = Map.get(spawn_def, :patrol_path) ->
        case Store.get_patrol_path(path_name) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            []
        end

      Map.get(spawn_def, :auto_spline, true) ->
        find_auto_spline(spline_index, world_id, position)

      true ->
        []
    end
  end

  defp find_auto_spline(spline_index, world_id, position) do
    case Store.find_nearest_spline_indexed(spline_index, world_id, position, max_distance: 15.0) do
      {:ok, spline_id, _distance} ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            []
        end

      :none ->
        []
    end
  end

  # Apply damage to a creature
  defp apply_damage_to_creature(creature_state, attacker_guid, damage, state) do
    entity = Entity.apply_damage(creature_state.entity, damage)
    ai = AI.add_threat(creature_state.ai, attacker_guid, damage)

    # Enter combat if not already
    ai =
      if not AI.in_combat?(ai) do
        AI.enter_combat(ai, attacker_guid)
      else
        ai
      end

    if Entity.dead?(entity) do
      handle_creature_death(creature_state, entity, attacker_guid, state)
    else
      new_creature_state = %{creature_state | entity: entity, ai: ai}

      result_info = %{
        remaining_health: entity.health,
        max_health: entity.max_health
      }

      {{:ok, :damaged, result_info}, new_creature_state, state}
    end
  end

  defp handle_creature_death(creature_state, entity, killer_guid, state) do
    killer_level = get_killer_level(killer_guid, creature_state.template.level, state)

    {result, new_creature_state} =
      CreatureDeath.handle_death(creature_state, entity, killer_guid, killer_level)

    {result, new_creature_state, state}
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

  # Process AI tick for all creatures in this zone
  defp process_ai_tick(state) do
    now = System.monotonic_time(:millisecond)

    creatures_needing_update =
      state.creature_states
      |> Enum.filter(fn {_guid, creature_state} ->
        needs_ai_processing?(creature_state, now)
      end)

    creature_states =
      Enum.reduce(creatures_needing_update, state.creature_states, fn {guid, creature_state},
                                                                      creature_states ->
        case process_creature_ai(creature_state, state, now) do
          {:no_change, _} ->
            creature_states

          {:updated, new_creature_state} ->
            Map.put(creature_states, guid, new_creature_state)
        end
      end)

    %{state | creature_states: creature_states}
  end

  defp needs_ai_processing?(%{ai: ai, template: template}, _now) do
    ai.state == :combat or
      ai.state == :evade or
      ai.state == :wandering or
      ai.state == :patrol or
      map_size(ai.threat_table) > 0 or
      (ai.state == :idle and ai.patrol_enabled) or
      (ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0)
  end

  defp process_creature_ai(%{ai: ai, template: template, entity: entity} = creature_state, state, now) do
    # For idle aggressive creatures, check for nearby players to aggro
    if ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0 do
      case check_aggro_nearby_players(creature_state, state) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(ai, player_guid)
          {:updated, %{creature_state | ai: new_ai}}

        nil ->
          process_creature_ai_tick(creature_state, ai, template, entity, state, now)
      end
    else
      process_creature_ai_tick(creature_state, ai, template, entity, state, now)
    end
  end

  defp check_aggro_nearby_players(creature_state, state) do
    creature_pos = creature_state.entity.position
    aggro_range = creature_state.template.aggro_range || 15.0
    creature_faction = creature_state.template.faction || :hostile

    nearby_players = get_nearby_players(state, creature_pos, aggro_range)
    AI.check_aggro_with_faction(creature_state.ai, nearby_players, aggro_range, creature_faction)
  end

  defp get_nearby_players(state, position, range) do
    state.players
    |> MapSet.to_list()
    |> Enum.map(&Map.get(state.entities, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn e -> AI.distance(e.position, position) <= range end)
    |> Enum.map(fn e ->
      %{
        guid: e.guid,
        position: e.position,
        faction: Map.get(e, :faction, :exile)
      }
    end)
  end

  defp process_creature_ai_tick(creature_state, ai, template, entity, state, now) do
    if ai.state == :combat do
      current_pos = entity.position
      leash_range = template.leash_range || 40.0

      case AI.check_leash(ai, current_pos, leash_range) do
        :evade ->
          new_ai = AI.start_evade(ai)
          {:updated, %{creature_state | ai: new_ai}}

        :ok ->
          process_combat_ai_tick(creature_state, ai, template, entity, state)
      end
    else
      process_normal_ai_tick(creature_state, ai, template, entity, state, now)
    end
  end

  defp process_combat_ai_tick(creature_state, ai, template, entity, state) do
    target_pos = get_target_position(creature_state, state)
    attack_range = CreatureTemplate.attack_range(template)

    case AI.combat_action(ai, target_pos, attack_range) do
      :none ->
        {:no_change, creature_state}

      :wait ->
        {:no_change, creature_state}

      {:attack, target_guid} ->
        current_pos = entity.position
        {tx, ty, tz} = target_pos
        {cx, cy, cz} = current_pos

        current_distance =
          :math.sqrt((tx - cx) * (tx - cx) + (ty - cy) * (ty - cy) + (tz - cz) * (tz - cz))

        min_range = if template.is_ranged, do: attack_range * 0.5, else: 0.0

        if template.is_ranged and current_distance < min_range do
          path = Movement.ranged_position_path(current_pos, target_pos, min_range, attack_range)

          if length(path) > 1 do
            path_length = Movement.path_length(path)
            duration = CreatureTemplate.movement_duration(template, path_length)
            new_ai = AI.start_chase(ai, path, duration)
            speed = CreatureTemplate.movement_speed(template)
            broadcast_creature_movement(entity.guid, path, speed, state.world_id)
            end_pos = List.last(path)
            new_entity = %{entity | position: end_pos}
            {:updated, %{creature_state | ai: new_ai, entity: new_entity}}
          else
            {:no_change, creature_state}
          end
        else
          if AI.chasing?(ai) do
            broadcast_creature_stop(entity.guid, state.world_id)
          end

          new_ai = AI.record_attack(ai) |> AI.complete_chase()
          apply_creature_attack(entity, template, target_guid, state)
          {:updated, %{creature_state | ai: new_ai}}
        end

      {:chase, chase_target_pos} ->
        current_pos = entity.position

        path =
          if template.is_ranged do
            min_range = attack_range * 0.5
            Movement.ranged_position_path(current_pos, chase_target_pos, min_range, attack_range)
          else
            Movement.chase_path(current_pos, chase_target_pos, attack_range)
          end

        if length(path) > 1 do
          path_length = Movement.path_length(path)
          duration = CreatureTemplate.movement_duration(template, path_length)
          new_ai = AI.start_chase(ai, path, duration)
          speed = CreatureTemplate.movement_speed(template)
          broadcast_creature_movement(entity.guid, path, speed, state.world_id)
          end_pos = List.last(path)
          new_entity = %{entity | position: end_pos}
          {:updated, %{creature_state | ai: new_ai, entity: new_entity}}
        else
          {:no_change, creature_state}
        end
    end
  end

  defp get_target_position(creature_state, state) do
    case Map.get(creature_state, :target_position) do
      nil ->
        target_guid = creature_state.ai.target_guid

        case Map.get(state.entities, target_guid) do
          nil -> creature_state.entity.position
          target -> target.position
        end

      pos ->
        pos
    end
  end

  defp process_normal_ai_tick(creature_state, ai, template, entity, state, _now) do
    context = %{
      attack_speed: template.attack_speed,
      position: entity.position
    }

    case AI.tick(ai, context) do
      :none ->
        {:no_change, creature_state}

      {:move_to, target_pos} ->
        current_pos = entity.position
        dist_to_target = AI.distance(current_pos, target_pos)

        if dist_to_target < 2.0 do
          if ai.state == :evade do
            new_ai = AI.complete_evade(ai)

            new_entity = %{
              entity
              | health: template.max_health,
                position: target_pos
            }

            {:updated, %{creature_state | ai: new_ai, entity: new_entity}}
          else
            {:no_change, creature_state}
          end
        else
          new_pos = move_toward(current_pos, target_pos, 5.0)
          new_entity = %{entity | position: new_pos}
          {:updated, %{creature_state | entity: new_entity}}
        end

      {:start_wander, new_ai} ->
        broadcast_creature_movement(
          entity.guid,
          new_ai.movement_path,
          new_ai.wander_speed,
          state.world_id
        )

        end_position = List.last(new_ai.movement_path) || entity.position
        new_entity = %{entity | position: end_position}
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}}

      {:wander_complete, new_ai} ->
        {:updated, %{creature_state | ai: new_ai}}

      {:start_patrol, new_ai} ->
        broadcast_creature_movement(
          entity.guid,
          new_ai.movement_path,
          new_ai.patrol_speed,
          state.world_id
        )

        end_position = List.last(new_ai.movement_path) || entity.position
        new_entity = %{entity | position: end_position}
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}}

      {:patrol_segment_complete, new_ai} ->
        {:updated, %{creature_state | ai: new_ai}}

      _ ->
        {:no_change, creature_state}
    end
  end

  defp move_toward({x1, y1, z1}, {x2, y2, z2}, step_distance) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    length = :math.sqrt(dx * dx + dy * dy + dz * dz)

    if length <= step_distance do
      {x2, y2, z2}
    else
      ratio = step_distance / length
      {x1 + dx * ratio, y1 + dy * ratio, z1 + dz * ratio}
    end
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
  defp broadcast_creature_movement(creature_guid, path, speed, world_id) when length(path) > 1 do
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

    __MODULE__.broadcast({world_id, 1}, {:server_entity_command, packet_data})
  end

  defp broadcast_creature_movement(_creature_guid, _path, _speed, _world_id), do: :ok

  defp broadcast_creature_stop(creature_guid, world_id) do
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

    __MODULE__.broadcast({world_id, 1}, {:server_entity_command, packet_data})
  end
end
