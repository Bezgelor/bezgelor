defmodule BezgelorWorld.EventManagerSupervisor do
  @moduledoc """
  Dynamic supervisor for EventManager instances.

  Each zone instance gets its own EventManager process to handle
  public events, world bosses, and zone-wide activities.

  ## Usage

      # Start an EventManager for a zone
      {:ok, pid} = EventManagerSupervisor.start_manager(zone_id, instance_id)

      # Stop an EventManager
      :ok = EventManagerSupervisor.stop_manager(zone_id, instance_id)
  """

  use DynamicSupervisor

  alias BezgelorWorld.EventManager
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
  Start an EventManager for a zone instance.
  """
  @spec start_manager(non_neg_integer(), non_neg_integer()) ::
          {:ok, pid()} | {:error, term()}
  def start_manager(zone_id, instance_id) do
    child_spec = {
      EventManager,
      [zone_id: zone_id, instance_id: instance_id]
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started EventManager for zone #{zone_id} instance #{instance_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("EventManager already running for zone #{zone_id} instance #{instance_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start EventManager: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stop an EventManager for a zone instance.
  """
  @spec stop_manager(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_manager(zone_id, instance_id) do
    case GenServer.whereis(EventManager.via_tuple(zone_id, instance_id)) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped EventManager for zone #{zone_id} instance #{instance_id}")
        :ok
    end
  end

  @doc """
  Get or start an EventManager for a zone instance.
  """
  @spec get_or_start_manager(non_neg_integer(), non_neg_integer()) ::
          {:ok, pid()} | {:error, term()}
  def get_or_start_manager(zone_id, instance_id) do
    case GenServer.whereis(EventManager.via_tuple(zone_id, instance_id)) do
      nil -> start_manager(zone_id, instance_id)
      pid -> {:ok, pid}
    end
  end

  @doc """
  List all running EventManagers.
  """
  @spec list_managers() :: [{non_neg_integer(), non_neg_integer(), pid()}]
  def list_managers do
    ProcessRegistry.list_with_meta(:event_manager)
    |> Enum.map(fn {{zone_id, instance_id}, pid, _meta} ->
      {zone_id, instance_id, pid}
    end)
  end
end
