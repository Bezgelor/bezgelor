defmodule BezgelorWorld.MythicPlus.MythicRun do
  @moduledoc """
  Manages an active Mythic+ dungeon run.

  Tracks:
  - Run timer and completion status
  - Death count and time penalties
  - Kill count (trash %)
  - Boss kills
  - Score calculation for leaderboards
  """

  use GenServer

  require Logger

  alias BezgelorWorld.MythicPlus.{Keystone, Affix}

  @death_penalty 5_000  # 5 second penalty per death

  defstruct [
    :instance_guid,
    :keystone,
    :time_limit,
    :start_time,
    :end_time,
    :status,           # :in_progress | :completed | :failed | :abandoned
    deaths: 0,
    trash_count: 0,
    trash_required: 0,
    bosses_killed: 0,
    bosses_required: 0,
    events: []
  ]

  @type t :: %__MODULE__{}

  # Client API

  def start_link(opts) do
    instance_guid = Keyword.fetch!(opts, :instance_guid)
    GenServer.start_link(__MODULE__, opts, name: via(instance_guid))
  end

  defp via(instance_guid) do
    {:via, Registry, {BezgelorWorld.Instance.Registry, {:mythic_run, instance_guid}}}
  end

  @doc """
  Starts the Mythic+ timer.
  """
  @spec start_run(non_neg_integer()) :: :ok
  def start_run(instance_guid) do
    GenServer.cast(via(instance_guid), :start_run)
  end

  @doc """
  Records a player death.
  """
  @spec record_death(non_neg_integer(), non_neg_integer()) :: :ok
  def record_death(instance_guid, character_id) do
    GenServer.cast(via(instance_guid), {:death, character_id})
  end

  @doc """
  Records trash kill count.
  """
  @spec record_trash_kill(non_neg_integer(), non_neg_integer()) :: :ok
  def record_trash_kill(instance_guid, count_value) do
    GenServer.cast(via(instance_guid), {:trash_kill, count_value})
  end

  @doc """
  Records a boss kill.
  """
  @spec record_boss_kill(non_neg_integer(), non_neg_integer()) :: :ok
  def record_boss_kill(instance_guid, boss_id) do
    GenServer.cast(via(instance_guid), {:boss_kill, boss_id})
  end

  @doc """
  Completes the run (final boss killed with trash requirement met).
  """
  @spec complete_run(non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def complete_run(instance_guid) do
    GenServer.call(via(instance_guid), :complete_run)
  end

  @doc """
  Abandons the run.
  """
  @spec abandon_run(non_neg_integer()) :: :ok
  def abandon_run(instance_guid) do
    GenServer.cast(via(instance_guid), :abandon)
  end

  @doc """
  Gets current run status.
  """
  @spec get_status(non_neg_integer()) :: map()
  def get_status(instance_guid) do
    GenServer.call(via(instance_guid), :get_status)
  end

  @doc """
  Gets affix effects that should be applied.
  """
  @spec process_affix_trigger(non_neg_integer(), atom(), map()) :: [map()]
  def process_affix_trigger(instance_guid, trigger, context) do
    GenServer.call(via(instance_guid), {:affix_trigger, trigger, context})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    keystone = Keyword.fetch!(opts, :keystone)
    dungeon_def = Keyword.get(opts, :dungeon_definition, %{})

    state = %__MODULE__{
      instance_guid: Keyword.fetch!(opts, :instance_guid),
      keystone: keystone,
      time_limit: Keystone.get_time_limit(keystone.dungeon_id, keystone.level),
      status: :in_progress,
      trash_required: dungeon_def["trash_count"] || 100,
      bosses_required: dungeon_def["boss_count"] || 3
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:start_run, state) do
    state = %{state |
      start_time: System.monotonic_time(:millisecond),
      events: [{:run_started, System.monotonic_time(:millisecond)} | state.events]
    }

    Logger.info("Mythic+ run started: #{state.keystone.dungeon_id} level #{state.keystone.level}")

    {:noreply, state}
  end

  def handle_cast({:death, character_id}, state) do
    state = %{state |
      deaths: state.deaths + 1,
      events: [{:death, character_id, System.monotonic_time(:millisecond)} | state.events]
    }

    Logger.info("Death recorded in M+ run, total: #{state.deaths}")

    {:noreply, state}
  end

  def handle_cast({:trash_kill, count_value}, state) do
    new_count = min(state.trash_count + count_value, state.trash_required)
    state = %{state | trash_count: new_count}

    {:noreply, state}
  end

  def handle_cast({:boss_kill, boss_id}, state) do
    state = %{state |
      bosses_killed: state.bosses_killed + 1,
      events: [{:boss_kill, boss_id, System.monotonic_time(:millisecond)} | state.events]
    }

    Logger.info("Boss killed in M+ run: #{boss_id}, total: #{state.bosses_killed}/#{state.bosses_required}")

    {:noreply, state}
  end

  def handle_cast(:abandon, state) do
    state = %{state |
      status: :abandoned,
      end_time: System.monotonic_time(:millisecond)
    }

    Logger.info("Mythic+ run abandoned")

    {:noreply, state}
  end

  @impl true
  def handle_call(:complete_run, _from, state) do
    if can_complete?(state) do
      end_time = System.monotonic_time(:millisecond)
      completion_time = calculate_completion_time(state, end_time)

      result = %{
        status: :completed,
        completion_time: completion_time,
        time_limit: state.time_limit,
        in_time: completion_time <= state.time_limit,
        deaths: state.deaths,
        time_bonus: Keystone.calculate_time_bonus(state.time_limit, completion_time),
        score: calculate_score(state, completion_time),
        keystone: state.keystone
      }

      state = %{state |
        status: :completed,
        end_time: end_time
      }

      Logger.info("Mythic+ run completed in #{completion_time}ms (limit: #{state.time_limit}ms)")

      {:reply, {:ok, result}, state}
    else
      {:reply, {:error, :requirements_not_met}, state}
    end
  end

  def handle_call(:get_status, _from, state) do
    elapsed = if state.start_time do
      System.monotonic_time(:millisecond) - state.start_time
    else
      0
    end

    status = %{
      status: state.status,
      elapsed_time: elapsed,
      time_limit: state.time_limit,
      remaining_time: max(0, state.time_limit - elapsed - state.deaths * @death_penalty),
      deaths: state.deaths,
      death_penalty: state.deaths * @death_penalty,
      trash_percent: div(state.trash_count * 100, max(1, state.trash_required)),
      bosses_killed: state.bosses_killed,
      bosses_required: state.bosses_required,
      keystone_level: state.keystone.level,
      affix_ids: state.keystone.affix_ids
    }

    {:reply, status, state}
  end

  def handle_call({:affix_trigger, trigger, context}, _from, state) do
    effects = Affix.process_trigger(trigger, state.keystone.affix_ids, context)
    {:reply, effects, state}
  end

  # Private Functions

  defp can_complete?(state) do
    state.bosses_killed >= state.bosses_required and
      state.trash_count >= state.trash_required and
      state.status == :in_progress
  end

  defp calculate_completion_time(state, end_time) do
    base_time = end_time - state.start_time
    penalty = state.deaths * @death_penalty
    base_time + penalty
  end

  defp calculate_score(state, completion_time) do
    # Base score from keystone level
    base_score = state.keystone.level * 100

    # Bonus for time
    time_bonus = cond do
      completion_time <= state.time_limit * 0.6 -> 50
      completion_time <= state.time_limit * 0.8 -> 30
      completion_time <= state.time_limit -> 10
      true -> 0
    end

    # Penalty for deaths (max -50)
    death_penalty = min(state.deaths * 5, 50)

    # Affix bonuses (more affixes = more points)
    affix_bonus = length(state.keystone.affix_ids) * 10

    max(0, base_score + time_bonus + affix_bonus - death_penalty)
  end
end
