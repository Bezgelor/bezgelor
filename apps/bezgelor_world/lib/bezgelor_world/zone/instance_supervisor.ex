defmodule BezgelorWorld.Zone.InstanceSupervisor do
  @moduledoc """
  Dynamic supervisor for zone instances.

  Manages the lifecycle of zone instance processes, starting and stopping
  them on demand. Each zone instance also gets a dedicated creature manager
  for handling creature AI in that zone.

  ## Usage

      # Start a new zone instance
      {:ok, pid} = InstanceSupervisor.start_instance(zone_id, instance_id, zone_data)

      # Stop an instance
      :ok = InstanceSupervisor.stop_instance(zone_id, instance_id)

      # List all instances
      instances = InstanceSupervisor.list_instances()
  """

  use DynamicSupervisor

  alias BezgelorWorld.Zone.Instance
  alias BezgelorWorld.Creature.ZoneManager, as: CreatureZoneManager
  alias BezgelorWorld.EventManagerSupervisor
  alias BezgelorWorld.ProcessLookup

  require Logger

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new zone instance.
  """
  @spec start_instance(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, pid()} | {:error, term()}
  def start_instance(zone_id, instance_id, zone_data \\ %{}) do
    child_spec = {
      Instance,
      [zone_id: zone_id, instance_id: instance_id, zone_data: zone_data]
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started zone instance: zone=#{zone_id} instance=#{instance_id}")

        # Start a per-zone creature manager for AI processing
        start_creature_manager(zone_id, instance_id)

        # Also start an EventManager for this zone instance
        EventManagerSupervisor.start_manager(zone_id, instance_id)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Zone instance already running: zone=#{zone_id} instance=#{instance_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start zone instance: #{inspect(reason)}")
        error
    end
  end

  # Start a creature manager for a zone instance
  defp start_creature_manager(zone_id, instance_id) do
    creature_spec = {
      CreatureZoneManager,
      [zone_id: zone_id, instance_id: instance_id]
    }

    case DynamicSupervisor.start_child(__MODULE__, creature_spec) do
      {:ok, _pid} ->
        Logger.debug("Started creature manager: zone=#{zone_id} instance=#{instance_id}")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start creature manager: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop a zone instance.
  """
  @spec stop_instance(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_instance(zone_id, instance_id) do
    case ProcessLookup.whereis(BezgelorWorld.ZoneRegistry, {zone_id, instance_id}) do
      nil ->
        {:error, :not_found}

      pid ->
        # Stop the creature manager first
        stop_creature_manager(zone_id, instance_id)

        # Stop the EventManager
        EventManagerSupervisor.stop_manager(zone_id, instance_id)

        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped zone instance: zone=#{zone_id} instance=#{instance_id}")
        :ok
    end
  end

  # Stop the creature manager for a zone instance
  defp stop_creature_manager(zone_id, instance_id) do
    case CreatureZoneManager.whereis(zone_id, instance_id) do
      nil ->
        :ok

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.debug("Stopped creature manager: zone=#{zone_id} instance=#{instance_id}")
        :ok
    end
  end

  @doc """
  Get or start a zone instance.

  Returns an existing instance if running, otherwise starts a new one.
  """
  @spec get_or_start_instance(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, pid()} | {:error, term()}
  def get_or_start_instance(zone_id, instance_id, zone_data \\ %{}) do
    case ProcessLookup.whereis(BezgelorWorld.ZoneRegistry, {zone_id, instance_id}) do
      nil -> start_instance(zone_id, instance_id, zone_data)
      pid -> {:ok, pid}
    end
  end

  @doc """
  List all running zone instances.
  """
  @spec list_instances() :: [{non_neg_integer(), non_neg_integer(), pid()}]
  def list_instances do
    ProcessLookup.list_with_meta(BezgelorWorld.ZoneRegistry)
    |> Enum.map(fn {{zone_id, instance_id}, pid, _meta} ->
      {zone_id, instance_id, pid}
    end)
  end

  @doc """
  List instances for a specific zone.
  """
  @spec list_instances_for_zone(non_neg_integer()) :: [{non_neg_integer(), pid()}]
  def list_instances_for_zone(zone_id) do
    list_instances()
    |> Enum.filter(fn {z_id, _i_id, _pid} -> z_id == zone_id end)
    |> Enum.map(fn {_z_id, i_id, pid} -> {i_id, pid} end)
  end

  @doc """
  Get instance count.
  """
  @spec instance_count() :: non_neg_integer()
  def instance_count do
    ProcessLookup.count(BezgelorWorld.ZoneRegistry)
  end

  @doc """
  Find the best instance to join for a zone (load balancing).

  For open world zones, returns the instance with the fewest players
  that isn't at capacity.
  """
  @spec find_best_instance(non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :no_instance}
  def find_best_instance(zone_id, max_players \\ 100) do
    instances = list_instances_for_zone(zone_id)

    case instances do
      [] ->
        {:error, :no_instance}

      _ ->
        # Find instance with lowest player count under capacity
        best =
          instances
          |> Enum.map(fn {instance_id, pid} ->
            info = Instance.info(pid)
            {instance_id, info.player_count}
          end)
          |> Enum.filter(fn {_id, count} -> count < max_players end)
          |> Enum.min_by(fn {_id, count} -> count end, fn -> nil end)

        case best do
          nil -> {:error, :no_instance}
          {instance_id, _count} -> {:ok, instance_id}
        end
    end
  end
end
