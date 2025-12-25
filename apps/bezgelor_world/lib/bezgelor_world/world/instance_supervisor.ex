defmodule BezgelorWorld.World.InstanceSupervisor do
  @moduledoc """
  Dynamic supervisor for world instances.

  Manages the lifecycle of world instance processes, starting and stopping
  them on demand. Each world instance also gets a dedicated creature manager
  for handling creature AI in that world.

  ## Usage

      # Start a new world instance
      {:ok, pid} = InstanceSupervisor.start_instance(world_id, instance_id, world_data)

      # Stop an instance
      :ok = InstanceSupervisor.stop_instance(world_id, instance_id)

      # List all instances
      instances = InstanceSupervisor.list_instances()
  """

  use DynamicSupervisor

  alias BezgelorWorld.World.Instance
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
  Start a new world instance.

  ## Options

    * `:lazy_loading` - Override lazy loading setting (default: from config)
  """
  @spec start_instance(non_neg_integer(), non_neg_integer(), map(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_instance(world_id, instance_id, world_data \\ %{}, opts \\ []) do
    lazy_loading =
      Keyword.get(
        opts,
        :lazy_loading,
        Application.get_env(:bezgelor_world, :lazy_zone_loading, false)
      )

    child_spec = {
      Instance,
      [world_id: world_id, instance_id: instance_id, world_data: world_data, lazy_loading: lazy_loading]
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.debug("Started world instance: world=#{world_id} instance=#{instance_id}")

        # Start a per-world creature manager for AI processing
        start_creature_manager(world_id, instance_id)

        # Also start an EventManager for this world instance
        EventManagerSupervisor.start_manager(world_id, instance_id)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("World instance already running: world=#{world_id} instance=#{instance_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start world instance: #{inspect(reason)}")
        error
    end
  end

  # Start a creature manager for a world instance
  defp start_creature_manager(world_id, instance_id) do
    creature_spec = {
      CreatureZoneManager,
      [zone_id: world_id, instance_id: instance_id]
    }

    case DynamicSupervisor.start_child(__MODULE__, creature_spec) do
      {:ok, _pid} ->
        Logger.debug("Started creature manager: world=#{world_id} instance=#{instance_id}")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start creature manager: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop a world instance.
  """
  @spec stop_instance(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_instance(world_id, instance_id) do
    case ProcessLookup.whereis(BezgelorWorld.WorldRegistry, {world_id, instance_id}) do
      nil ->
        {:error, :not_found}

      pid ->
        # Stop the creature manager first
        stop_creature_manager(world_id, instance_id)

        # Stop the EventManager
        EventManagerSupervisor.stop_manager(world_id, instance_id)

        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped world instance: world=#{world_id} instance=#{instance_id}")
        :ok
    end
  end

  # Stop the creature manager for a world instance
  defp stop_creature_manager(world_id, instance_id) do
    case CreatureZoneManager.whereis(world_id, instance_id) do
      nil ->
        :ok

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.debug("Stopped creature manager: world=#{world_id} instance=#{instance_id}")
        :ok
    end
  end

  @doc """
  Get or start a world instance.

  Returns an existing instance if running, otherwise starts a new one.
  """
  @spec get_or_start_instance(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, pid()} | {:error, term()}
  def get_or_start_instance(world_id, instance_id, world_data \\ %{}) do
    case ProcessLookup.whereis(BezgelorWorld.WorldRegistry, {world_id, instance_id}) do
      nil -> start_instance(world_id, instance_id, world_data)
      pid -> {:ok, pid}
    end
  end

  @doc """
  List all running world instances.
  """
  @spec list_instances() :: [{non_neg_integer(), non_neg_integer(), pid()}]
  def list_instances do
    ProcessLookup.list_with_meta(BezgelorWorld.WorldRegistry)
    |> Enum.map(fn {{world_id, instance_id}, pid, _meta} ->
      {world_id, instance_id, pid}
    end)
  end

  @doc """
  List instances for a specific world.
  """
  @spec list_instances_for_world(non_neg_integer()) :: [{non_neg_integer(), pid()}]
  def list_instances_for_world(world_id) do
    list_instances()
    |> Enum.filter(fn {w_id, _i_id, _pid} -> w_id == world_id end)
    |> Enum.map(fn {_w_id, i_id, pid} -> {i_id, pid} end)
  end

  @doc """
  Get instance count.
  """
  @spec instance_count() :: non_neg_integer()
  def instance_count do
    ProcessLookup.count(BezgelorWorld.WorldRegistry)
  end

  @doc """
  Find the best instance to join for a world (load balancing).

  For open world zones, returns the instance with the fewest players
  that isn't at capacity.
  """
  @spec find_best_instance(non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :no_instance}
  def find_best_instance(world_id, max_players \\ 100) do
    instances = list_instances_for_world(world_id)

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

  @doc """
  List world IDs that have at least one player.

  Used for AI optimization to only process creatures in worlds with active players.
  Returns a MapSet of world_ids for O(1) membership checking.
  """
  @spec list_worlds_with_players() :: MapSet.t(non_neg_integer())
  def list_worlds_with_players do
    list_instances()
    |> Enum.filter(fn {_world_id, _instance_id, pid} ->
      try do
        Instance.player_count(pid) > 0
      catch
        :exit, _ -> false
      end
    end)
    |> Enum.map(fn {world_id, _instance_id, _pid} -> world_id end)
    |> MapSet.new()
  end
end
