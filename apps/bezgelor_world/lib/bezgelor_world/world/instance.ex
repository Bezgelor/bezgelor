defmodule BezgelorWorld.World.Instance do
  @moduledoc """
  World instance GenServer.

  Each instance represents an active shard of a world containing:
  - Entities (players, creatures, objects)
  - World-specific state
  - Spatial index for range queries

  ## Important: world_id vs zone_id

  This module is keyed by `world_id`, NOT `zone_id`. In WildStar:
  - `world_id` identifies the map/continent (e.g., 1634 = Gambler's Ruin)
  - `zone_id` identifies a sub-region within a world (e.g., 4844 = Cryo Awakening Protocol)

  When looking up a World.Instance, always use `world_id` from session_data.

  ## Instance Types

  - **Open World**: Shared instances (e.g., main world zones)
  - **Dungeon**: Private instances per group
  - **Housing**: Private instances per player/guild

  ## Usage

      # Add a player to the world instance
      World.Instance.add_entity({world_id, instance_id}, player_entity)

      # Find entities in range
      World.Instance.entities_in_range({world_id, instance_id}, {x, y, z}, 100.0)

      # Broadcast to all entities
      World.Instance.broadcast({world_id, instance_id}, {:chat, sender, message})
  """

  use GenServer

  alias BezgelorCore.{Entity, SpatialGrid}
  alias BezgelorWorld.{CreatureManager, HarvestNodeManager}

  require Logger

  @type instance_id :: non_neg_integer()

  @type state :: %{
          world_id: non_neg_integer(),
          instance_id: instance_id(),
          world_data: map(),
          entities: %{non_neg_integer() => Entity.t()},
          spatial_grid: SpatialGrid.t(),
          players: MapSet.t(non_neg_integer()),
          creatures: MapSet.t(non_neg_integer())
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

  # Server Callbacks

  @impl true
  def init(opts) do
    world_id = Keyword.fetch!(opts, :world_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    world_data = Keyword.get(opts, :world_data, %{})

    # Note: Registration with metadata happens via the :via tuple in start_link
    # The Registry stores metadata as the value during registration

    state = %{
      world_id: world_id,
      instance_id: instance_id,
      world_data: world_data,
      entities: %{},
      spatial_grid: SpatialGrid.new(50.0),
      players: MapSet.new(),
      creatures: MapSet.new()
    }

    Logger.info("World instance started: #{world_data[:name] || world_id} (instance #{instance_id})")

    # Load creature spawns asynchronously after init completes
    {:ok, state, {:continue, :load_spawns}}
  end

  @impl true
  def handle_continue(:load_spawns, state) do
    # Load spawns asynchronously - don't block world startup
    # Managers log results directly
    CreatureManager.load_zone_spawns_async(state.world_id)
    HarvestNodeManager.load_zone_spawns_async(state.world_id)

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
end
