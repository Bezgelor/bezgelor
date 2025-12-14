defmodule BezgelorWorld.Zone.Instance do
  @moduledoc """
  Zone instance GenServer.

  Each instance represents an active shard of a zone containing:
  - Entities (players, creatures, objects)
  - Zone-specific state
  - Spatial index for range queries

  ## Instance Types

  - **Open World**: Shared instances (e.g., main world zones)
  - **Dungeon**: Private instances per group
  - **Housing**: Private instances per player/guild

  ## Usage

      # Add a player to the zone
      Zone.Instance.add_entity(instance, player_entity)

      # Find entities in range
      Zone.Instance.entities_in_range(instance, {x, y, z}, 100.0)

      # Broadcast to all entities
      Zone.Instance.broadcast(instance, {:chat, sender, message})
  """

  use GenServer

  alias BezgelorCore.{Entity, SpatialGrid}
  alias BezgelorWorld.{CreatureManager, HarvestNodeManager}

  require Logger

  @type instance_id :: non_neg_integer()

  @type state :: %{
          zone_id: non_neg_integer(),
          instance_id: instance_id(),
          zone_data: map(),
          entities: %{non_neg_integer() => Entity.t()},
          spatial_grid: SpatialGrid.t(),
          players: MapSet.t(non_neg_integer()),
          creatures: MapSet.t(non_neg_integer())
        }

  # Client API

  @doc """
  Start a zone instance.
  """
  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)

    GenServer.start_link(__MODULE__, opts, name: via_tuple(zone_id, instance_id))
  end

  @doc """
  Get the registry name for a zone instance.
  """
  def via_tuple(zone_id, instance_id) do
    {:via, Registry, {BezgelorWorld.ZoneRegistry, {zone_id, instance_id}}}
  end

  @doc """
  Add an entity to the zone.
  """
  @spec add_entity(pid() | {non_neg_integer(), instance_id()}, Entity.t()) :: :ok
  def add_entity(instance, %Entity{} = entity) when is_pid(instance) do
    GenServer.cast(instance, {:add_entity, entity})
  end

  def add_entity({zone_id, instance_id}, %Entity{} = entity) do
    GenServer.cast(via_tuple(zone_id, instance_id), {:add_entity, entity})
  end

  @doc """
  Remove an entity from the zone.
  """
  @spec remove_entity(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) :: :ok
  def remove_entity(instance, guid) when is_pid(instance) do
    GenServer.cast(instance, {:remove_entity, guid})
  end

  def remove_entity({zone_id, instance_id}, guid) do
    GenServer.cast(via_tuple(zone_id, instance_id), {:remove_entity, guid})
  end

  @doc """
  Get an entity by GUID.
  """
  @spec get_entity(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          {:ok, Entity.t()} | :error
  def get_entity(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_entity, guid})
  end

  def get_entity({zone_id, instance_id}, guid) do
    GenServer.call(via_tuple(zone_id, instance_id), {:get_entity, guid})
  end

  @doc """
  Get the creature_id (template ID) for an entity by GUID.

  Returns {:ok, creature_id} if the entity exists and is a creature,
  or :error if not found or not a creature.
  """
  @spec get_entity_creature_id(pid() | {non_neg_integer(), instance_id()}, non_neg_integer()) ::
          {:ok, non_neg_integer()} | :error
  def get_entity_creature_id(instance, guid) when is_pid(instance) do
    GenServer.call(instance, {:get_entity_creature_id, guid})
  end

  def get_entity_creature_id({zone_id, instance_id}, guid) do
    GenServer.call(via_tuple(zone_id, instance_id), {:get_entity_creature_id, guid})
  end

  @doc """
  Update an entity's state.
  """
  @spec update_entity(pid() | {non_neg_integer(), instance_id()}, non_neg_integer(), (Entity.t() -> Entity.t())) ::
          :ok | :error
  def update_entity(instance, guid, update_fn) when is_pid(instance) do
    GenServer.call(instance, {:update_entity, guid, update_fn})
  end

  def update_entity({zone_id, instance_id}, guid, update_fn) do
    GenServer.call(via_tuple(zone_id, instance_id), {:update_entity, guid, update_fn})
  end

  @doc """
  Update an entity's position efficiently.

  This is more efficient than update_entity when only the position changes,
  as it avoids the overhead of a full entity update.
  """
  @spec update_entity_position(pid() | {non_neg_integer(), instance_id()}, non_neg_integer(), Entity.position()) ::
          :ok | :error
  def update_entity_position(instance, guid, position) when is_pid(instance) do
    GenServer.call(instance, {:update_entity_position, guid, position})
  end

  def update_entity_position({zone_id, instance_id}, guid, position) do
    GenServer.call(via_tuple(zone_id, instance_id), {:update_entity_position, guid, position})
  end

  @doc """
  Find entities within range of a position.
  """
  @spec entities_in_range(pid() | {non_neg_integer(), instance_id()}, Entity.position(), float()) ::
          [Entity.t()]
  def entities_in_range(instance, position, radius) when is_pid(instance) do
    GenServer.call(instance, {:entities_in_range, position, radius})
  end

  def entities_in_range({zone_id, instance_id}, position, radius) do
    GenServer.call(via_tuple(zone_id, instance_id), {:entities_in_range, position, radius})
  end

  @doc """
  Get all players in the zone.
  """
  @spec list_players(pid() | {non_neg_integer(), instance_id()}) :: [Entity.t()]
  def list_players(instance) when is_pid(instance) do
    GenServer.call(instance, :list_players)
  end

  def list_players({zone_id, instance_id}) do
    GenServer.call(via_tuple(zone_id, instance_id), :list_players)
  end

  @doc """
  Get player count in the zone.
  """
  @spec player_count(pid() | {non_neg_integer(), instance_id()}) :: non_neg_integer()
  def player_count(instance) when is_pid(instance) do
    GenServer.call(instance, :player_count)
  end

  def player_count({zone_id, instance_id}) do
    GenServer.call(via_tuple(zone_id, instance_id), :player_count)
  end

  @doc """
  Broadcast a message to all player entities in the zone.
  """
  @spec broadcast(pid() | {non_neg_integer(), instance_id()}, term()) :: :ok
  def broadcast(instance, message) when is_pid(instance) do
    GenServer.cast(instance, {:broadcast, message})
  end

  def broadcast({zone_id, instance_id}, message) do
    GenServer.cast(via_tuple(zone_id, instance_id), {:broadcast, message})
  end

  @doc """
  Get zone info.
  """
  @spec info(pid() | {non_neg_integer(), instance_id()}) :: map()
  def info(instance) when is_pid(instance) do
    GenServer.call(instance, :info)
  end

  def info({zone_id, instance_id}) do
    GenServer.call(via_tuple(zone_id, instance_id), :info)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    zone_data = Keyword.get(opts, :zone_data, %{})

    # Note: Registration with metadata happens via the :via tuple in start_link
    # The Registry stores metadata as the value during registration

    state = %{
      zone_id: zone_id,
      instance_id: instance_id,
      zone_data: zone_data,
      entities: %{},
      spatial_grid: SpatialGrid.new(50.0),
      players: MapSet.new(),
      creatures: MapSet.new()
    }

    Logger.info("Zone instance started: #{zone_data[:name] || zone_id} (instance #{instance_id})")

    # Load creature spawns asynchronously after init completes
    {:ok, state, {:continue, :load_spawns}}
  end

  @impl true
  def handle_continue(:load_spawns, state) do
    # Load creature spawns for this zone from static data
    case CreatureManager.load_zone_spawns(state.zone_id) do
      {:ok, count} ->
        Logger.info("Zone #{state.zone_id}: loaded #{count} creature spawns")

      {:error, :not_found} ->
        Logger.debug("Zone #{state.zone_id}: no spawn data found")

      {:error, reason} ->
        Logger.warning("Zone #{state.zone_id}: failed to load spawns: #{inspect(reason)}")
    end

    # Load harvest node spawns for this zone
    case HarvestNodeManager.load_zone_spawns(state.zone_id) do
      {:ok, 0} ->
        Logger.debug("Zone #{state.zone_id}: no harvest nodes found")

      {:ok, count} ->
        Logger.info("Zone #{state.zone_id}: loaded #{count} harvest nodes")

      {:error, reason} ->
        Logger.warning("Zone #{state.zone_id}: failed to load harvest nodes: #{inspect(reason)}")
    end

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
          %{state | entities: entities, spatial_grid: spatial_grid, players: MapSet.put(state.players, entity.guid)}

        :creature ->
          %{state | entities: entities, spatial_grid: spatial_grid, creatures: MapSet.put(state.creatures, entity.guid)}

        _ ->
          %{state | entities: entities, spatial_grid: spatial_grid}
      end

    Logger.debug("Entity #{entity.guid} (#{entity.type}) added to zone #{state.zone_id}")
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
            %{state | entities: entities, spatial_grid: spatial_grid, players: MapSet.delete(state.players, guid)}

          :creature ->
            %{state | entities: entities, spatial_grid: spatial_grid, creatures: MapSet.delete(state.creatures, guid)}

          _ ->
            %{state | entities: entities, spatial_grid: spatial_grid}
        end
      else
        %{state | entities: entities, spatial_grid: spatial_grid}
      end

    Logger.debug("Entity #{guid} removed from zone #{state.zone_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    # Broadcast to all player connection processes
    # This requires knowing the connection PIDs, which we'd get from WorldManager sessions
    # For now, log and skip actual broadcast
    Logger.debug(
      "Zone #{state.zone_id} broadcast: #{inspect(message)} to #{MapSet.size(state.players)} players"
    )

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
      zone_id: state.zone_id,
      instance_id: state.instance_id,
      zone_name: Map.get(state.zone_data, :name, "Unknown"),
      player_count: MapSet.size(state.players),
      creature_count: MapSet.size(state.creatures),
      total_entities: map_size(state.entities)
    }

    {:reply, info, state}
  end
end
