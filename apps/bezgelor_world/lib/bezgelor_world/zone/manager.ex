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

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  require Logger

  # Tutorial arkship worlds that need to be started even without spawn data
  # These are the "Cryo Awakening Protocol" instances where new characters spawn
  @tutorial_worlds [
    {1634, 4844, "Gambler's Ruin (Exile Tutorial)"},
    {1537, 4813, "Destiny (Dominion Tutorial)"}
  ]

  # Maximum concurrent zone starts - scales with CPU cores (minimum 20 for 4-core, up to 50 for 8+ cores)
  @max_concurrent_zone_starts max(20, min(50, System.schedulers_online() * 5))

  # Zone start timeout - default 120 seconds, configurable for slow hardware (e.g., Fly.io shared CPUs)
  @default_zone_start_timeout 120_000

  @doc """
  Initialize default zone instances asynchronously.

  Called at application startup to create the main world zone instances.
  Zones are started concurrently using Task.async_stream for faster startup.
  Also starts tutorial zones which may not have spawn data.
  """
  @spec initialize_zones() :: :ok
  def initialize_zones do
    # Start zones that have spawn data (from NexusForever WorldDatabase)
    spawn_zones = BezgelorData.Store.get_all_spawn_zones()

    zone_timeout = Application.get_env(:bezgelor_world, :zone_start_timeout, @default_zone_start_timeout)

    Logger.info(
      "Starting #{length(spawn_zones)} spawn zones (concurrency=#{@max_concurrent_zone_starts}, timeout=#{zone_timeout}ms)..."
    )

    # Start zones concurrently with bounded parallelism
    spawn_started =
      spawn_zones
      |> Task.async_stream(
        fn zone_data ->
          start_spawn_zone(zone_data)
        end,
        max_concurrency: @max_concurrent_zone_starts,
        timeout: zone_timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce(0, fn
        {:ok, 1}, acc ->
          acc + 1

        {:ok, 0}, acc ->
          acc

        {:exit, reason}, acc ->
          Logger.warning("Zone start task crashed: #{inspect(reason)}")
          acc
      end)

    # Start tutorial zones (they don't have spawn data but need to be running)
    tutorial_started = start_tutorial_zones()

    total = spawn_started + tutorial_started

    Logger.info(
      "Initialized #{total} zone instances (#{spawn_started} spawn zones + #{tutorial_started} tutorial zones)"
    )

    :ok
  rescue
    # BezgelorData may not be started yet, or no zones defined
    error ->
      Logger.warning("Failed to initialize zones: #{inspect(error)}")
      :ok
  end

  # Start a single spawn zone (called from async task)
  defp start_spawn_zone(zone_data) do
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
        Logger.debug("Started zone instance: zone=#{zone_id} (#{zone_name})")
        1

      {:error, {:already_started, _pid}} ->
        # Already started, that's fine
        0

      {:error, reason} ->
        Logger.warning("Failed to start zone #{zone_id}: #{inspect(reason)}")
        0
    end
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
  def get_instance_for_zone(zone_id) when is_integer(zone_id) and zone_id > 0 do
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

  def get_instance_for_zone(_zone_id), do: {:error, :invalid_zone_id}

  @doc """
  Get the best instance for a player to join.

  Considers current load for open world zones.
  """
  @spec get_instance_for_player(non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), pid()}} | {:error, term()}
  def get_instance_for_player(zone_id, opts \\ [])

  def get_instance_for_player(zone_id, opts) when is_integer(zone_id) and zone_id > 0 do
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

  def get_instance_for_player(_zone_id, _opts), do: {:error, :invalid_zone_id}

  @doc """
  Add an entity to a zone instance.
  """
  @spec add_entity_to_zone(non_neg_integer(), non_neg_integer(), Entity.t()) :: :ok
  def add_entity_to_zone(zone_id, instance_id, entity)
      when is_integer(zone_id) and zone_id > 0 and is_integer(instance_id) and instance_id > 0 do
    Instance.add_entity({zone_id, instance_id}, entity)
  end

  @doc """
  Remove an entity from a zone instance.
  """
  @spec remove_entity_from_zone(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def remove_entity_from_zone(zone_id, instance_id, entity_guid)
      when is_integer(zone_id) and zone_id > 0 and is_integer(instance_id) and instance_id > 0 do
    Instance.remove_entity({zone_id, instance_id}, entity_guid)
  end

  @doc """
  Transfer a player from one zone to another.
  """
  @spec transfer_player(Entity.t(), {non_neg_integer(), non_neg_integer()}, non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def transfer_player(entity, {from_zone_id, from_instance_id}, to_zone_id)
      when is_integer(from_zone_id) and from_zone_id > 0 and
             is_integer(from_instance_id) and from_instance_id > 0 and
             is_integer(to_zone_id) and to_zone_id > 0 do
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

  def transfer_player(_entity, _from, _to), do: {:error, :invalid_zone_id}

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
      InstanceSupervisor.list_instances_for_world(zone_id)
      |> Enum.map(fn {id, _pid} -> id end)

    max_id = Enum.max(existing, fn -> 0 end)
    max_id + 1
  end
end
