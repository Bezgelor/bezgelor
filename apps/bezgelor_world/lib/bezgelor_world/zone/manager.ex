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

  @doc """
  Initialize default zone instances.

  Called at application startup to create the main world zone instances.
  """
  @spec initialize_zones() :: :ok
  def initialize_zones do
    zones = BezgelorData.list_zones()

    for zone <- zones do
      # Skip dungeons - they're created on demand
      unless Map.get(zone, :is_dungeon, false) do
        # Create instance 1 for each open world zone
        {:ok, _pid} = InstanceSupervisor.start_instance(zone.id, 1, zone)
      end
    end

    Logger.info("Initialized #{length(zones)} zone templates")
    :ok
  rescue
    # BezgelorData may not be started yet, or no zones defined
    error ->
      Logger.warning("Failed to initialize zones: #{inspect(error)}")
      :ok
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
