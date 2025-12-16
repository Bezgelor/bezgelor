defmodule BezgelorWorld.DeathManager do
  @moduledoc """
  Manages player death state and respawn timers.

  Tracks which players are dead, pending resurrection offers,
  and handles the resurrection/respawn flow.

  ## State Structure

      %{
        dead_players: %{
          player_guid => %{
            zone_id: integer,
            position: {float, float, float},
            killer_guid: integer | nil,
            died_at: integer (monotonic ms),
            res_offer: nil | %{
              caster_guid: integer,
              spell_id: integer,
              health_percent: float,
              timeout_at: integer (monotonic ms)
            }
          }
        }
      }
  """
  use GenServer

  require Logger

  alias BezgelorCore.Death

  # Resurrection offer timeout (60 seconds)
  @res_offer_timeout_ms 60_000

  # Default bindpoint (Thayd starting zone)
  @default_bindpoint %{zone_id: 426, position: {3949.0, -855.0, -1929.0}}

  @type player_guid :: non_neg_integer()
  @type position :: {float(), float(), float()}

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start the DeathManager GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Mark a player as dead.
  """
  @spec player_died(player_guid(), non_neg_integer(), position(), player_guid() | nil) :: :ok
  def player_died(player_guid, zone_id, position, killer_guid) do
    GenServer.cast(__MODULE__, {:player_died, player_guid, zone_id, position, killer_guid})
  end

  @doc """
  Check if a player is currently dead.
  """
  @spec is_dead?(player_guid()) :: boolean()
  def is_dead?(player_guid) do
    GenServer.call(__MODULE__, {:is_dead, player_guid})
  end

  @doc """
  Get death information for a player.
  """
  @spec get_death_info(player_guid()) :: {:ok, map()} | {:error, :not_dead}
  def get_death_info(player_guid) do
    GenServer.call(__MODULE__, {:get_death_info, player_guid})
  end

  @doc """
  Offer resurrection to a dead player.
  """
  @spec offer_resurrection(player_guid(), player_guid(), non_neg_integer(), float()) ::
          :ok | {:error, :not_dead}
  def offer_resurrection(player_guid, caster_guid, spell_id, health_percent) do
    GenServer.call(__MODULE__, {:offer_resurrection, player_guid, caster_guid, spell_id, health_percent})
  end

  @doc """
  Player accepts a pending resurrection offer.
  """
  @spec accept_resurrection(player_guid()) ::
          {:ok, %{position: position(), health_percent: float(), resurrect_type: atom()}}
          | {:error, :not_dead | :no_offer}
  def accept_resurrection(player_guid) do
    GenServer.call(__MODULE__, {:accept_resurrection, player_guid})
  end

  @doc """
  Player declines a pending resurrection offer.
  """
  @spec decline_resurrection(player_guid()) :: :ok
  def decline_resurrection(player_guid) do
    GenServer.cast(__MODULE__, {:decline_resurrection, player_guid})
  end

  @doc """
  Player respawns at their bindpoint.
  """
  @spec respawn_at_bindpoint(player_guid()) ::
          {:ok, %{zone_id: non_neg_integer(), position: position(), health_percent: float(), resurrect_type: atom()}}
          | {:error, :not_dead}
  def respawn_at_bindpoint(player_guid) do
    GenServer.call(__MODULE__, {:respawn_at_bindpoint, player_guid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    {:ok, %{dead_players: %{}}}
  end

  @impl true
  def handle_cast({:player_died, player_guid, zone_id, position, killer_guid}, state) do
    death_info = %{
      zone_id: zone_id,
      position: position,
      killer_guid: killer_guid,
      died_at: System.monotonic_time(:millisecond),
      res_offer: nil
    }

    new_state = put_in(state, [:dead_players, player_guid], death_info)
    Logger.debug("Player #{player_guid} died at zone #{zone_id}")

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:decline_resurrection, player_guid}, state) do
    new_state =
      case get_in(state, [:dead_players, player_guid]) do
        nil ->
          state

        death_info ->
          updated_info = %{death_info | res_offer: nil}
          put_in(state, [:dead_players, player_guid], updated_info)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:is_dead, player_guid}, _from, state) do
    is_dead = Map.has_key?(state.dead_players, player_guid)
    {:reply, is_dead, state}
  end

  @impl true
  def handle_call({:get_death_info, player_guid}, _from, state) do
    result =
      case Map.get(state.dead_players, player_guid) do
        nil -> {:error, :not_dead}
        info -> {:ok, info}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:offer_resurrection, player_guid, caster_guid, spell_id, health_percent}, _from, state) do
    case Map.get(state.dead_players, player_guid) do
      nil ->
        {:reply, {:error, :not_dead}, state}

      death_info ->
        res_offer = %{
          caster_guid: caster_guid,
          spell_id: spell_id,
          health_percent: health_percent,
          timeout_at: System.monotonic_time(:millisecond) + @res_offer_timeout_ms
        }

        updated_info = %{death_info | res_offer: res_offer}
        new_state = put_in(state, [:dead_players, player_guid], updated_info)

        Logger.debug("Resurrection offered to player #{player_guid} by #{caster_guid}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:accept_resurrection, player_guid}, _from, state) do
    case Map.get(state.dead_players, player_guid) do
      nil ->
        {:reply, {:error, :not_dead}, state}

      %{res_offer: nil} ->
        {:reply, {:error, :no_offer}, state}

      %{res_offer: offer, position: position} ->
        # Check if offer hasn't timed out
        now = System.monotonic_time(:millisecond)

        if now > offer.timeout_at do
          {:reply, {:error, :no_offer}, state}
        else
          # Remove from dead players
          new_state = update_in(state, [:dead_players], &Map.delete(&1, player_guid))

          result = %{
            position: position,
            health_percent: offer.health_percent,
            resurrect_type: :spell
          }

          Logger.debug("Player #{player_guid} accepted resurrection")
          {:reply, {:ok, result}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:respawn_at_bindpoint, player_guid}, _from, state) do
    case Map.get(state.dead_players, player_guid) do
      nil ->
        {:reply, {:error, :not_dead}, state}

      _death_info ->
        # TODO: Look up character's actual bindpoint from database
        # For now, use default bindpoint
        bindpoint = get_bindpoint_for_player(player_guid)

        # Calculate respawn health based on level
        # TODO: Look up actual player level
        level = 50
        health_percent = Death.respawn_health_percent(level)

        # Remove from dead players
        new_state = update_in(state, [:dead_players], &Map.delete(&1, player_guid))

        result = %{
          zone_id: bindpoint.zone_id,
          position: bindpoint.position,
          health_percent: health_percent,
          resurrect_type: :bindpoint
        }

        Logger.debug("Player #{player_guid} respawning at bindpoint zone #{bindpoint.zone_id}")
        {:reply, {:ok, result}, new_state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_bindpoint_for_player(_player_guid) do
    # TODO: Look up from character data in database
    # For now return default bindpoint
    @default_bindpoint
  end
end
