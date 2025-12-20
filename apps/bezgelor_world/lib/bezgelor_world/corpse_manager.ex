defmodule BezgelorWorld.CorpseManager do
  @moduledoc """
  Manages corpse entities across the game world.

  Corpses are created when creatures die and contain loot that players can pick up.
  Each corpse has a despawn timer and tracks which players have looted it.

  ## Features

  - Spawn corpses from dead creatures with loot
  - Track loot state per player (each player can loot once)
  - Automatic despawn after timeout
  - Query corpses by zone for efficient zone updates
  """

  use GenServer

  alias BezgelorCore.Entity

  require Logger

  @type state :: %{
          corpses: %{non_neg_integer() => Entity.t()},
          zone_index: %{non_neg_integer() => MapSet.t()}
        }

  ## Client API

  @doc "Start the CorpseManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Spawn a corpse entity from a dead creature with loot.

  Returns `{:ok, corpse_guid}` on success.
  """
  @spec spawn_corpse(Entity.t(), [Entity.loot_item()]) :: {:ok, non_neg_integer()}
  def spawn_corpse(%Entity{} = creature, loot) when is_list(loot) do
    GenServer.call(__MODULE__, {:spawn_corpse, creature, loot})
  end

  @doc """
  Get a corpse by its GUID.

  Returns `{:ok, corpse}` or `{:error, :not_found}`.
  """
  @spec get_corpse(non_neg_integer()) :: {:ok, Entity.t()} | {:error, :not_found}
  def get_corpse(corpse_guid) do
    GenServer.call(__MODULE__, {:get_corpse, corpse_guid})
  end

  @doc """
  Take loot from a corpse for a specific player.

  Returns `{:ok, loot_items}` where loot_items is a list of `{item_id, quantity}` tuples.
  Returns empty list if player has already looted or corpse doesn't exist.
  """
  @spec take_loot(non_neg_integer(), non_neg_integer()) ::
          {:ok, [Entity.loot_item()]} | {:error, :not_found}
  def take_loot(corpse_guid, player_guid) do
    GenServer.call(__MODULE__, {:take_loot, corpse_guid, player_guid})
  end

  @doc """
  Check if a corpse has loot available for a specific player.
  """
  @spec has_loot_for?(non_neg_integer(), non_neg_integer()) :: boolean()
  def has_loot_for?(corpse_guid, player_guid) do
    GenServer.call(__MODULE__, {:has_loot_for?, corpse_guid, player_guid})
  end

  @doc """
  Despawn a corpse, removing it from the manager.
  """
  @spec despawn_corpse(non_neg_integer()) :: :ok
  def despawn_corpse(corpse_guid) do
    GenServer.call(__MODULE__, {:despawn_corpse, corpse_guid})
  end

  @doc """
  Get all corpses in a specific zone.
  """
  @spec get_corpses_in_zone(non_neg_integer()) :: [Entity.t()]
  def get_corpses_in_zone(zone_id) do
    GenServer.call(__MODULE__, {:get_corpses_in_zone, zone_id})
  end

  @doc """
  Clear all corpses (for testing).
  """
  @spec clear_all() :: :ok
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      corpses: %{},
      zone_index: %{}
    }

    Logger.info("CorpseManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:spawn_corpse, creature, loot}, _from, state) do
    corpse = Entity.create_corpse(creature, loot)
    corpse_guid = corpse.guid
    zone_id = corpse.zone_id

    # Add to corpses map
    corpses = Map.put(state.corpses, corpse_guid, corpse)

    # Add to zone index
    zone_corpses = Map.get(state.zone_index, zone_id, MapSet.new())
    zone_index = Map.put(state.zone_index, zone_id, MapSet.put(zone_corpses, corpse_guid))

    # Schedule despawn
    despawn_delay = corpse.despawn_at - System.monotonic_time(:millisecond)

    if despawn_delay > 0 do
      Process.send_after(self(), {:despawn, corpse_guid}, despawn_delay)
    end

    state = %{state | corpses: corpses, zone_index: zone_index}

    Logger.debug(
      "Spawned corpse #{corpse_guid} from creature #{creature.guid} in zone #{zone_id}"
    )

    {:reply, {:ok, corpse_guid}, state}
  end

  @impl true
  def handle_call({:get_corpse, corpse_guid}, _from, state) do
    case Map.get(state.corpses, corpse_guid) do
      nil -> {:reply, {:error, :not_found}, state}
      corpse -> {:reply, {:ok, corpse}, state}
    end
  end

  @impl true
  def handle_call({:take_loot, corpse_guid, player_guid}, _from, state) do
    case Map.get(state.corpses, corpse_guid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      corpse ->
        {updated_corpse, loot_items} = Entity.take_loot(corpse, player_guid)
        corpses = Map.put(state.corpses, corpse_guid, updated_corpse)
        state = %{state | corpses: corpses}

        Logger.debug(
          "Player #{player_guid} looted corpse #{corpse_guid}: #{length(loot_items)} items"
        )

        {:reply, {:ok, loot_items}, state}
    end
  end

  @impl true
  def handle_call({:has_loot_for?, corpse_guid, player_guid}, _from, state) do
    result =
      case Map.get(state.corpses, corpse_guid) do
        nil -> false
        corpse -> Entity.has_loot_for?(corpse, player_guid)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:despawn_corpse, corpse_guid}, _from, state) do
    state = do_despawn(state, corpse_guid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_corpses_in_zone, zone_id}, _from, state) do
    corpse_guids = Map.get(state.zone_index, zone_id, MapSet.new())

    corpses =
      corpse_guids
      |> Enum.map(&Map.get(state.corpses, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, corpses, state}
  end

  @impl true
  def handle_call(:clear_all, _from, _state) do
    state = %{
      corpses: %{},
      zone_index: %{}
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:despawn, corpse_guid}, state) do
    Logger.debug("Auto-despawning corpse #{corpse_guid}")
    state = do_despawn(state, corpse_guid)
    {:noreply, state}
  end

  # Private helpers

  defp do_despawn(state, corpse_guid) do
    case Map.get(state.corpses, corpse_guid) do
      nil ->
        state

      corpse ->
        zone_id = corpse.zone_id

        # Remove from corpses map
        corpses = Map.delete(state.corpses, corpse_guid)

        # Remove from zone index
        zone_corpses = Map.get(state.zone_index, zone_id, MapSet.new())
        zone_index = Map.put(state.zone_index, zone_id, MapSet.delete(zone_corpses, corpse_guid))

        Logger.debug("Despawned corpse #{corpse_guid} from zone #{zone_id}")
        %{state | corpses: corpses, zone_index: zone_index}
    end
  end
end
