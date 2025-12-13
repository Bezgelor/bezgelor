defmodule BezgelorWorld.Instance.Instance do
  @moduledoc """
  GenServer managing a single instance (dungeon, adventure, raid, expedition).

  Each instance process manages:
  - Player membership and permissions
  - Boss encounter states
  - Lockout tracking
  - Loot distribution
  - Mythic+ timer and affixes (if applicable)
  - Instance completion and reset

  ## State Lifecycle

  1. `:initializing` - Loading instance data
  2. `:waiting` - Waiting for players to enter
  3. `:active` - Players inside, encounters available
  4. `:boss_engaged` - Boss fight in progress
  5. `:completed` - Instance cleared
  6. `:resetting` - Soft reset in progress

  ## Instance Types

  - `:dungeon` - 5-player dungeons (Stormtalon's Lair, etc.)
  - `:adventure` - 5-player adventures (story-driven)
  - `:raid` - 20/40-player raids
  - `:expedition` - Ship combat instances
  """
  use GenServer

  alias BezgelorDb.Achievements
  alias BezgelorWorld.Instance.Registry, as: InstanceRegistry
  alias BezgelorWorld.Instance.BossEncounter
  alias BezgelorData.Store

  require Logger

  @idle_timeout :timer.minutes(30)
  @boss_engaged_timeout :timer.minutes(30)

  defstruct [
    :instance_guid,
    :definition_id,
    :definition,
    :difficulty,
    :group_id,
    :leader_id,
    :zone_id,
    :mythic_level,
    :affix_ids,
    state: :initializing,
    players: %{},
    bosses: %{},
    defeated_bosses: MapSet.new(),
    trash_killed: 0,
    trash_required: 0,
    start_time: nil,
    end_time: nil,
    loot_mode: :personal,
    deaths: 0,
    mythic_timer_start: nil
  ]

  @type t :: %__MODULE__{
          instance_guid: non_neg_integer(),
          definition_id: non_neg_integer(),
          definition: map() | nil,
          difficulty: :normal | :veteran | :challenge | :mythic_plus,
          group_id: non_neg_integer() | nil,
          leader_id: non_neg_integer() | nil,
          zone_id: non_neg_integer() | nil,
          mythic_level: non_neg_integer(),
          affix_ids: [non_neg_integer()],
          state: atom(),
          players: map(),
          bosses: map(),
          defeated_bosses: MapSet.t(),
          trash_killed: non_neg_integer(),
          trash_required: non_neg_integer(),
          start_time: DateTime.t() | nil,
          end_time: DateTime.t() | nil,
          loot_mode: atom(),
          deaths: non_neg_integer(),
          mythic_timer_start: integer() | nil
        }

  @type player_info :: %{
          character_id: non_neg_integer(),
          name: String.t(),
          role: :tank | :healer | :dps,
          class_id: non_neg_integer(),
          level: non_neg_integer(),
          inside: boolean(),
          alive: boolean()
        }

  # Client API

  @doc """
  Starts an instance process.
  """
  def start_link(opts) do
    instance_guid = Keyword.fetch!(opts, :instance_guid)
    GenServer.start_link(__MODULE__, opts, name: InstanceRegistry.via(instance_guid))
  end

  @doc """
  Adds a player to the instance.
  """
  @spec add_player(non_neg_integer(), player_info()) :: :ok | {:error, term()}
  def add_player(instance_guid, player_info) do
    GenServer.call(via(instance_guid), {:add_player, player_info})
  end

  @doc """
  Removes a player from the instance.
  """
  @spec remove_player(non_neg_integer(), non_neg_integer()) :: :ok
  def remove_player(instance_guid, character_id) do
    GenServer.call(via(instance_guid), {:remove_player, character_id})
  end

  @doc """
  Marks a player as having entered the instance zone.
  """
  @spec player_entered(non_neg_integer(), non_neg_integer()) :: :ok
  def player_entered(instance_guid, character_id) do
    GenServer.call(via(instance_guid), {:player_entered, character_id})
  end

  @doc """
  Marks a player as having left the instance zone.
  """
  @spec player_left(non_neg_integer(), non_neg_integer()) :: :ok
  def player_left(instance_guid, character_id) do
    GenServer.call(via(instance_guid), {:player_left, character_id})
  end

  @doc """
  Records a player death.
  """
  @spec player_died(non_neg_integer(), non_neg_integer()) :: :ok
  def player_died(instance_guid, character_id) do
    GenServer.cast(via(instance_guid), {:player_died, character_id})
  end

  @doc """
  Records a player resurrection.
  """
  @spec player_resurrected(non_neg_integer(), non_neg_integer()) :: :ok
  def player_resurrected(instance_guid, character_id) do
    GenServer.cast(via(instance_guid), {:player_resurrected, character_id})
  end

  @doc """
  Engages a boss encounter.
  """
  @spec engage_boss(non_neg_integer(), non_neg_integer()) ::
          {:ok, pid()} | {:error, term()}
  def engage_boss(instance_guid, boss_id) do
    GenServer.call(via(instance_guid), {:engage_boss, boss_id})
  end

  @doc """
  Reports boss defeat.
  """
  @spec boss_defeated(non_neg_integer(), non_neg_integer()) :: :ok
  def boss_defeated(instance_guid, boss_id) do
    GenServer.cast(via(instance_guid), {:boss_defeated, boss_id})
  end

  @doc """
  Reports boss wipe.
  """
  @spec boss_wiped(non_neg_integer(), non_neg_integer()) :: :ok
  def boss_wiped(instance_guid, boss_id) do
    GenServer.cast(via(instance_guid), {:boss_wiped, boss_id})
  end

  @doc """
  Records trash mob kill (for Mythic+).
  """
  @spec trash_killed(non_neg_integer(), non_neg_integer()) :: :ok
  def trash_killed(instance_guid, count \\ 1) do
    GenServer.cast(via(instance_guid), {:trash_killed, count})
  end

  @doc """
  Gets the current instance state.
  """
  @spec get_state(non_neg_integer()) :: {:ok, t()} | {:error, :not_found}
  def get_state(instance_guid) do
    GenServer.call(via(instance_guid), :get_state)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  @doc """
  Gets instance info for packets.
  """
  @spec get_info(non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def get_info(instance_guid) do
    GenServer.call(via(instance_guid), :get_info)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  @doc """
  Resets the instance (leader only).
  """
  @spec reset(non_neg_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def reset(instance_guid, character_id) do
    GenServer.call(via(instance_guid), {:reset, character_id})
  end

  @doc """
  Sets the loot mode.
  """
  @spec set_loot_mode(non_neg_integer(), atom()) :: :ok | {:error, term()}
  def set_loot_mode(instance_guid, mode) do
    GenServer.call(via(instance_guid), {:set_loot_mode, mode})
  end

  @doc """
  Starts the Mythic+ timer.
  """
  @spec start_mythic_timer(non_neg_integer()) :: :ok
  def start_mythic_timer(instance_guid) do
    GenServer.cast(via(instance_guid), :start_mythic_timer)
  end

  @doc """
  Gets Mythic+ timer status.
  """
  @spec get_mythic_timer(non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def get_mythic_timer(instance_guid) do
    GenServer.call(via(instance_guid), :get_mythic_timer)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    instance_guid = Keyword.fetch!(opts, :instance_guid)
    definition_id = Keyword.fetch!(opts, :definition_id)
    difficulty = Keyword.fetch!(opts, :difficulty)

    state = %__MODULE__{
      instance_guid: instance_guid,
      definition_id: definition_id,
      difficulty: difficulty,
      group_id: Keyword.get(opts, :group_id),
      leader_id: Keyword.get(opts, :leader_id),
      mythic_level: Keyword.get(opts, :mythic_level, 0),
      affix_ids: Keyword.get(opts, :affix_ids, [])
    }

    # Load instance definition async
    send(self(), :load_definition)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_definition_id, _from, state) do
    {:reply, state.definition_id, state}
  end

  def handle_call({:add_player, player_info}, _from, state) do
    player = Map.merge(player_info, %{inside: false, alive: true})
    players = Map.put(state.players, player_info.character_id, player)

    Logger.debug("Player #{player_info.character_id} added to instance #{state.instance_guid}")

    {:reply, :ok, %{state | players: players}}
  end

  def handle_call({:remove_player, character_id}, _from, state) do
    players = Map.delete(state.players, character_id)
    state = %{state | players: players}

    # Check if instance is now empty
    state = maybe_schedule_cleanup(state)

    {:reply, :ok, state}
  end

  def handle_call({:player_entered, character_id}, _from, state) do
    state =
      update_player(state, character_id, fn player ->
        %{player | inside: true}
      end)

    state =
      if state.state == :waiting do
        %{state | state: :active, start_time: DateTime.utc_now()}
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:player_left, character_id}, _from, state) do
    state =
      update_player(state, character_id, fn player ->
        %{player | inside: false}
      end)

    state = maybe_schedule_cleanup(state)

    {:reply, :ok, state}
  end

  def handle_call({:engage_boss, boss_id}, _from, state) do
    case Map.get(state.bosses, boss_id) do
      nil ->
        # Start boss encounter process
        case start_boss_encounter(state, boss_id) do
          {:ok, pid} ->
            bosses = Map.put(state.bosses, boss_id, %{pid: pid, state: :engaged})
            state = %{state | bosses: bosses, state: :boss_engaged}
            {:reply, {:ok, pid}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end

      %{state: :defeated} ->
        {:reply, {:error, :already_defeated}, state}

      %{pid: pid, state: :engaged} ->
        {:reply, {:ok, pid}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_info, _from, state) do
    info = %{
      instance_guid: state.instance_guid,
      definition_id: state.definition_id,
      name: get_in(state.definition, ["name"]) || "Unknown",
      difficulty: state.difficulty,
      state: state.state,
      bosses_total: count_bosses(state),
      bosses_defeated: MapSet.size(state.defeated_bosses),
      mythic_level: state.mythic_level,
      player_count: map_size(state.players)
    }

    {:reply, {:ok, info}, state}
  end

  def handle_call({:reset, character_id}, _from, state) do
    cond do
      state.leader_id != character_id ->
        {:reply, {:error, :not_leader}, state}

      state.state == :boss_engaged ->
        {:reply, {:error, :boss_engaged}, state}

      MapSet.size(state.defeated_bosses) == 0 ->
        {:reply, {:error, :nothing_to_reset}, state}

      true ->
        state = do_reset(state)
        {:reply, :ok, state}
    end
  end

  def handle_call({:set_loot_mode, mode}, _from, state)
      when mode in [:personal, :need_greed, :master, :round_robin] do
    {:reply, :ok, %{state | loot_mode: mode}}
  end

  def handle_call(:get_mythic_timer, _from, state) do
    if state.difficulty == :mythic_plus and state.mythic_timer_start do
      elapsed = System.monotonic_time(:millisecond) - state.mythic_timer_start
      time_limit = get_mythic_time_limit(state)

      timer_info = %{
        elapsed_ms: elapsed,
        time_limit_ms: time_limit,
        plus_two_ms: div(time_limit * 80, 100),
        plus_three_ms: div(time_limit * 60, 100),
        trash_percent: calculate_trash_percent(state),
        trash_required: 100,
        bosses_killed: MapSet.size(state.defeated_bosses),
        bosses_total: count_bosses(state),
        deaths: state.deaths,
        death_penalty_ms: state.deaths * 5000
      }

      {:reply, {:ok, timer_info}, state}
    else
      {:reply, {:error, :not_mythic}, state}
    end
  end

  @impl true
  def handle_cast({:player_died, character_id}, state) do
    state =
      state
      |> update_player(character_id, fn player -> %{player | alive: false} end)
      |> Map.update!(:deaths, &(&1 + 1))

    # Check for wipe
    state =
      if all_dead?(state) do
        handle_wipe(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast({:player_resurrected, character_id}, state) do
    state = update_player(state, character_id, fn player -> %{player | alive: true} end)
    {:noreply, state}
  end

  def handle_cast({:boss_defeated, boss_id}, state) do
    state =
      state
      |> Map.update!(:defeated_bosses, &MapSet.put(&1, boss_id))
      |> put_in([:bosses, boss_id, :state], :defeated)
      |> Map.put(:state, :active)

    # Check for instance completion
    state =
      if instance_complete?(state) do
        complete_instance(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast({:boss_wiped, boss_id}, state) do
    # Remove boss process, allow re-engage
    state =
      state
      |> update_in([:bosses, boss_id], fn boss ->
        if boss, do: Map.delete(boss, :pid), else: nil
      end)
      |> Map.put(:state, :active)

    {:noreply, state}
  end

  def handle_cast({:trash_killed, count}, state) do
    state = Map.update!(state, :trash_killed, &(&1 + count))
    {:noreply, state}
  end

  def handle_cast(:start_mythic_timer, state) do
    if state.difficulty == :mythic_plus and is_nil(state.mythic_timer_start) do
      {:noreply, %{state | mythic_timer_start: System.monotonic_time(:millisecond)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:load_definition, state) do
    state =
      case Store.get_instance(state.definition_id) do
        {:ok, definition} ->
          trash_required = calculate_trash_required(definition, state.difficulty)
          zone_id = Map.get(definition, "zone_id", 0)

          %{state |
            definition: definition,
            zone_id: zone_id,
            trash_required: trash_required,
            state: :waiting
          }

        :error ->
          Logger.warning("Instance definition #{state.definition_id} not found")
          %{state | state: :waiting}
      end

    {:noreply, state}
  end

  def handle_info(:idle_timeout, state) do
    if players_inside?(state) do
      {:noreply, state}
    else
      Logger.info("Instance #{state.instance_guid} idle timeout - shutting down")
      {:stop, :normal, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp via(instance_guid), do: InstanceRegistry.via(instance_guid)

  defp update_player(state, character_id, update_fn) do
    case Map.get(state.players, character_id) do
      nil -> state
      player -> put_in(state, [:players, character_id], update_fn.(player))
    end
  end

  defp start_boss_encounter(state, boss_id) do
    # Find boss definition
    boss_def = find_boss_definition(state, boss_id)

    opts = [
      instance_guid: state.instance_guid,
      boss_id: boss_id,
      boss_definition: boss_def,
      difficulty: state.difficulty,
      mythic_level: state.mythic_level,
      affix_ids: state.affix_ids,
      players: state.players
    ]

    BossEncounter.start_link(opts)
  end

  defp find_boss_definition(state, boss_id) do
    # First try static data
    case Store.get_instance_boss(boss_id) do
      {:ok, boss} -> boss
      :error ->
        # Fall back to definition's boss list
        bosses = get_in(state.definition, ["bosses"]) || []
        Enum.find(bosses, fn b -> b["id"] == boss_id end) || %{"id" => boss_id}
    end
  end

  defp count_bosses(state) do
    case state.definition do
      %{"bosses" => bosses} when is_list(bosses) -> length(bosses)
      _ -> 0
    end
  end

  defp instance_complete?(state) do
    total = count_bosses(state)
    defeated = MapSet.size(state.defeated_bosses)

    total > 0 and defeated >= total and
      (state.difficulty != :mythic_plus or
         calculate_trash_percent(state) >= 100)
  end

  defp complete_instance(state) do
    Logger.info("Instance #{state.instance_guid} completed!")

    # Broadcast dungeon completion achievement to all players
    instance_id = state.definition_id

    Enum.each(state.players, fn {_player_id, player_info} ->
      if character_id = player_info[:character_id] do
        Achievements.broadcast(character_id, {:dungeon_complete, instance_id})
      end
    end)

    %{state |
      state: :completed,
      end_time: DateTime.utc_now()
    }
  end

  defp handle_wipe(state) do
    Logger.info("Wipe in instance #{state.instance_guid}")

    # Reset all alive players
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | alive: true}}
      end)

    # Notify boss encounters of wipe
    Enum.each(state.bosses, fn {boss_id, boss_info} ->
      if boss_info[:pid] && Process.alive?(boss_info[:pid]) do
        BossEncounter.wipe(boss_info[:pid])
      end
    end)

    %{state | players: players, state: :active}
  end

  defp do_reset(state) do
    Logger.info("Resetting instance #{state.instance_guid}")

    %{state |
      state: :resetting,
      defeated_bosses: MapSet.new(),
      trash_killed: 0,
      deaths: 0,
      mythic_timer_start: nil
    }
    |> then(fn s -> %{s | state: :waiting} end)
  end

  defp maybe_schedule_cleanup(state) do
    if not players_inside?(state) do
      Process.send_after(self(), :idle_timeout, @idle_timeout)
    end
    state
  end

  defp players_inside?(state) do
    Enum.any?(state.players, fn {_id, player} -> player.inside end)
  end

  defp all_dead?(state) do
    inside_players = Enum.filter(state.players, fn {_id, p} -> p.inside end)
    inside_players != [] and Enum.all?(inside_players, fn {_id, p} -> not p.alive end)
  end

  defp calculate_trash_required(definition, difficulty) do
    base = Map.get(definition, "trash_count", 0)

    case difficulty do
      :mythic_plus -> base
      :veteran -> div(base, 2)
      _ -> 0
    end
  end

  defp calculate_trash_percent(state) do
    if state.trash_required > 0 do
      min(100, div(state.trash_killed * 100, state.trash_required))
    else
      100
    end
  end

  defp get_mythic_time_limit(state) do
    base_time =
      case state.definition do
        %{"time_limit" => limit} -> limit
        _ -> 30 * 60 * 1000  # 30 minutes default
      end

    # Scale time limit based on mythic level
    scale = max(1.0 - (state.mythic_level - 1) * 0.02, 0.5)
    round(base_time * scale)
  end
end
