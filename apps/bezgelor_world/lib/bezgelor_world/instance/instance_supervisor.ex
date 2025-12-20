defmodule BezgelorWorld.Instance.Supervisor do
  @moduledoc """
  DynamicSupervisor for instance processes.

  Manages the lifecycle of instance processes, spawning new instances
  when groups are formed and cleaning up when instances complete or
  timeout.
  """
  use DynamicSupervisor

  import Bitwise

  alias BezgelorWorld.Instance.Instance
  alias BezgelorWorld.Instance.Registry, as: InstanceRegistry

  require Logger

  @doc """
  Starts the instance supervisor.
  """
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new instance process.

  ## Parameters
    - `instance_guid` - Unique identifier for this instance
    - `definition_id` - ID of the instance definition (from static data)
    - `difficulty` - Instance difficulty (:normal, :veteran, :challenge, :mythic_plus)
    - `opts` - Additional options:
      - `:group_id` - Group that owns this instance
      - `:leader_id` - Character ID of group leader
      - `:mythic_level` - Mythic+ keystone level (for :mythic_plus difficulty)
      - `:affix_ids` - Active affixes (for :mythic_plus difficulty)
  """
  @spec start_instance(non_neg_integer(), non_neg_integer(), atom(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_instance(instance_guid, definition_id, difficulty, opts \\ []) do
    spec =
      {Instance,
       [
         instance_guid: instance_guid,
         definition_id: definition_id,
         difficulty: difficulty,
         group_id: Keyword.get(opts, :group_id),
         leader_id: Keyword.get(opts, :leader_id),
         mythic_level: Keyword.get(opts, :mythic_level, 0),
         affix_ids: Keyword.get(opts, :affix_ids, [])
       ]}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info(
          "Started instance #{instance_guid} (def: #{definition_id}, diff: #{difficulty})"
        )

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start instance #{instance_guid}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops an instance process.
  """
  @spec stop_instance(non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_instance(instance_guid) do
    case InstanceRegistry.lookup(instance_guid) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped instance #{instance_guid}")
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets the process for an instance.
  """
  @spec get_instance(non_neg_integer()) :: {:ok, pid()} | {:error, :not_found}
  def get_instance(instance_guid) do
    case InstanceRegistry.lookup(instance_guid) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Checks if an instance exists.
  """
  @spec instance_exists?(non_neg_integer()) :: boolean()
  def instance_exists?(instance_guid) do
    case InstanceRegistry.lookup(instance_guid) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  @doc """
  Lists all active instances.
  """
  @spec list_instances() :: [{non_neg_integer(), pid()}]
  def list_instances do
    InstanceRegistry.list_instances()
  end

  @doc """
  Counts active instances.
  """
  @spec count_instances() :: non_neg_integer()
  def count_instances do
    InstanceRegistry.count_instances()
  end

  @doc """
  Generates a new unique instance GUID.
  """
  @spec generate_instance_guid() :: non_neg_integer()
  def generate_instance_guid do
    # Use System.unique_integer for uniqueness
    # Add timestamp component for sortability
    timestamp = System.system_time(:millisecond)
    unique = System.unique_integer([:positive, :monotonic]) &&& 0xFFFFFF
    timestamp <<< 24 ||| unique
  end
end
