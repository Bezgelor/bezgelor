defmodule BezgelorWorld.Zone.InstanceSupervisor do
  @moduledoc """
  Dynamic supervisor for zone instances.

  Manages the lifecycle of zone instance processes, starting and stopping
  them on demand.

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
  alias BezgelorWorld.EventManagerSupervisor
  alias BezgelorCore.ProcessRegistry

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

  @doc """
  Stop a zone instance.
  """
  @spec stop_instance(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_instance(zone_id, instance_id) do
    case ProcessRegistry.whereis(:zone_instance, {zone_id, instance_id}) do
      nil ->
        {:error, :not_found}

      pid ->
        # Stop the EventManager first
        EventManagerSupervisor.stop_manager(zone_id, instance_id)
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped zone instance: zone=#{zone_id} instance=#{instance_id}")
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
    case ProcessRegistry.whereis(:zone_instance, {zone_id, instance_id}) do
      nil -> start_instance(zone_id, instance_id, zone_data)
      pid -> {:ok, pid}
    end
  end

  @doc """
  List all running zone instances.
  """
  @spec list_instances() :: [{non_neg_integer(), non_neg_integer(), pid()}]
  def list_instances do
    ProcessRegistry.list_with_meta(:zone_instance)
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
    ProcessRegistry.count(:zone_instance)
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
