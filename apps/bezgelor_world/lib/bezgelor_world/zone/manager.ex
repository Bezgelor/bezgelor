defmodule BezgelorWorld.Zone.Manager do
  @moduledoc """
  High-level zone management API.

  Provides a simplified interface for working with zones:
  - Initialize zones on startup
  - Player zone transfers
  - Zone queries

  ## Usage

      # Initialize all zones from data
      Zone.Manager.initialize_zones()

      # Get or create instance for a player
      {:ok, instance_pid} = Zone.Manager.get_instance_for_player(zone_id)

      # Transfer player between zones
      :ok = Zone.Manager.transfer_player(entity, from_zone, to_zone)
  """

  alias BezgelorWorld.Zone.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  require Logger

  # Tutorial arkship worlds that need to be started even without spawn data
  # These are the "Cryo Awakening Protocol" instances where new characters spawn
  @tutorial_worlds [
    {1634, 4844, "Gambler's Ruin (Exile Tutorial)"},
    {1537, 4813, "Destiny (Dominion Tutorial)"}
  ]

  @doc """
  Initialize default zone instances.

  Called at application startup to create the main world zone instances.
  Also starts tutorial zones which may not have spawn data.
  """
  @spec initialize_zones() :: :ok
  def initialize_zones do
    # Start zones that have spawn data (from NexusForever WorldDatabase)
    spawn_zones = BezgelorData.Store.get_all_spawn_zones()

    spawn_started =
      for zone_data <- spawn_zones do
        zone_id = zone_data.world_id
        zone_name = zone_data.zone_name

        # Get zone metadata if available, otherwise create minimal stub
        zone =
          case BezgelorData.get_zone(zone_id) do
            {:ok, z} -> z
            :error -> %{id: zone_id, name: zone_name}
          end

        case InstanceSupervisor.start_instance(zone_id, 1, zone) do
          {:ok, _pid} ->
            Logger.info("Started zone instance: zone=#{zone_id} (#{zone_name})")
            1

          {:error, reason} ->
            Logger.warning("Failed to start zone #{zone_id}: #{inspect(reason)}")
            0
        end
      end

    # Start tutorial zones (they don't have spawn data but need to be running)
    tutorial_started = start_tutorial_zones()

    total = Enum.sum(spawn_started) + tutorial_started
    Logger.info("Initialized #{total} zone instances (#{Enum.sum(spawn_started)} spawn zones + #{tutorial_started} tutorial zones)")
    :ok
  rescue
    # BezgelorData may not be started yet, or no zones defined
    error ->
      Logger.warning("Failed to initialize zones: #{inspect(error)}")
      :ok
  end

  # Start tutorial zones even though they don't have creature spawn data
  defp start_tutorial_zones do
    @tutorial_worlds
    |> Enum.map(fn {world_id, zone_id, name} ->
      zone = %{
        id: zone_id,
        world_id: world_id,
        name: name,
        is_tutorial: true
      }

      case InstanceSupervisor.start_instance(world_id, 1, zone) do
        {:ok, _pid} ->
          Logger.info("Started tutorial zone: world=#{world_id} zone=#{zone_id} (#{name})")
          1

        {:error, {:already_started, _pid}} ->
          # Already started from spawn data, that's fine
          Logger.debug("Tutorial zone already running: #{name}")
          0

        {:error, reason} ->
          Logger.warning("Failed to start tutorial zone #{name}: #{inspect(reason)}")
          0
      end
    end)
    |> Enum.sum()
  end

  @doc """
  Get the primary instance for a zone, creating if needed.

  For open world zones, returns instance 1.
  For dungeons, creates a new instance.
  """
  @spec get_instance_for_zone(non_neg_integer()) :: {:ok, pid()} | {:error, term()}
  def get_instance_for_zone(zone_id) do
    zone_data = get_zone_data(zone_id)

    if Map.get(zone_data, :is_dungeon, false) do
      # Dungeons need a new instance each time
      instance_id = System.unique_integer([:positive])
      InstanceSupervisor.start_instance(zone_id, instance_id, zone_data)
    else
      # Open world - use instance 1
      InstanceSupervisor.get_or_start_instance(zone_id, 1, zone_data)
    end
  end

  @doc """
  Get the best instance for a player to join.

  Considers current load for open world zones.
  """
  @spec get_instance_for_player(non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), pid()}} | {:error, term()}
  def get_instance_for_player(zone_id, opts \\ []) do
    zone_data = get_zone_data(zone_id)
    max_players = Keyword.get(opts, :max_players, 100)

    if Map.get(zone_data, :is_dungeon, false) do
      # Dungeons: create new instance
      instance_id = System.unique_integer([:positive])

      case InstanceSupervisor.start_instance(zone_id, instance_id, zone_data) do
        {:ok, pid} -> {:ok, {instance_id, pid}}
        error -> error
      end
    else
      # Open world: find best instance or create overflow
      case InstanceSupervisor.find_best_instance(zone_id, max_players) do
        {:ok, instance_id} ->
          case InstanceSupervisor.get_or_start_instance(zone_id, instance_id, zone_data) do
            {:ok, pid} -> {:ok, {instance_id, pid}}
            error -> error
          end

        {:error, :no_instance} ->
          # Create new overflow instance
          instance_id = generate_instance_id(zone_id)

          case InstanceSupervisor.start_instance(zone_id, instance_id, zone_data) do
            {:ok, pid} -> {:ok, {instance_id, pid}}
            error -> error
          end
      end
    end
  end

  @doc """
  Add an entity to a zone instance.
  """
  @spec add_entity_to_zone(non_neg_integer(), non_neg_integer(), Entity.t()) :: :ok
  def add_entity_to_zone(zone_id, instance_id, entity) do
    Instance.add_entity({zone_id, instance_id}, entity)
  end

  @doc """
  Remove an entity from a zone instance.
  """
  @spec remove_entity_from_zone(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def remove_entity_from_zone(zone_id, instance_id, entity_guid) do
    Instance.remove_entity({zone_id, instance_id}, entity_guid)
  end

  @doc """
  Transfer a player from one zone to another.
  """
  @spec transfer_player(Entity.t(), {non_neg_integer(), non_neg_integer()}, non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def transfer_player(entity, {from_zone_id, from_instance_id}, to_zone_id) do
    # Remove from old zone
    Instance.remove_entity({from_zone_id, from_instance_id}, entity.guid)

    # Get instance in new zone
    case get_instance_for_player(to_zone_id) do
      {:ok, {to_instance_id, _pid}} ->
        # Add to new zone
        Instance.add_entity({to_zone_id, to_instance_id}, entity)
        {:ok, {to_zone_id, to_instance_id}}

      error ->
        # Rollback - add back to old zone
        Instance.add_entity({from_zone_id, from_instance_id}, entity)
        error
    end
  end

  @doc """
  Get zone status information.
  """
  @spec zone_status() :: [map()]
  def zone_status do
    InstanceSupervisor.list_instances()
    |> Enum.map(fn {zone_id, instance_id, pid} ->
      Instance.info(pid)
      |> Map.put(:zone_id, zone_id)
      |> Map.put(:instance_id, instance_id)
    end)
  end

  # Private

  defp get_zone_data(zone_id) do
    case BezgelorData.get_zone(zone_id) do
      {:ok, zone} -> zone
      :error -> %{id: zone_id, name: "Unknown Zone #{zone_id}"}
    end
  rescue
    # BezgelorData may not be available
    _ -> %{id: zone_id, name: "Unknown Zone #{zone_id}"}
  end

  defp generate_instance_id(zone_id) do
    existing =
      InstanceSupervisor.list_instances_for_zone(zone_id)
      |> Enum.map(fn {id, _pid} -> id end)

    max_id = Enum.max(existing, fn -> 0 end)
    max_id + 1
  end
end
