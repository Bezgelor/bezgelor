defmodule BezgelorWorld.PvP.BattlegroundQueue do
  @moduledoc """
  Manages battleground queue and matchmaking.

  Handles:
  - Player queue registration
  - Team formation based on faction
  - Match creation when teams are ready
  - Queue time tracking
  """

  use GenServer

  require Logger

  alias BezgelorData.Store

  # Queue configuration
  @min_players_per_team 4
  @max_players_per_team 10
  @queue_pop_check_interval 5_000
  @max_queue_time_ms 1_800_000

  defstruct [
    :player_guid,
    :player_name,
    :faction,
    :level,
    :class_id,
    :queued_at
  ]

  @type queue_entry :: %__MODULE__{
          player_guid: non_neg_integer(),
          player_name: String.t(),
          faction: :exile | :dominion,
          level: non_neg_integer(),
          class_id: non_neg_integer(),
          queued_at: integer()
        }

  @type queue_state :: %{
          queues: %{non_neg_integer() => %{exile: [queue_entry()], dominion: [queue_entry()]}},
          player_queues: %{non_neg_integer() => {non_neg_integer(), reference()}},
          active_instances: MapSet.t(String.t())
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Join the queue for a specific battleground.
  Returns {:ok, estimated_wait} or {:error, reason}.
  """
  @spec join_queue(
          non_neg_integer(),
          String.t(),
          :exile | :dominion,
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def join_queue(player_guid, player_name, faction, level, class_id, battleground_id) do
    GenServer.call(
      __MODULE__,
      {:join_queue, player_guid, player_name, faction, level, class_id, battleground_id}
    )
  end

  @doc """
  Leave the battleground queue.
  """
  @spec leave_queue(non_neg_integer()) :: :ok | {:error, :not_in_queue}
  def leave_queue(player_guid) do
    GenServer.call(__MODULE__, {:leave_queue, player_guid})
  end

  @doc """
  Check if a player is in queue.
  """
  @spec in_queue?(non_neg_integer()) :: boolean()
  def in_queue?(player_guid) do
    GenServer.call(__MODULE__, {:in_queue?, player_guid})
  end

  @doc """
  Get queue status for a player.
  """
  @spec get_queue_status(non_neg_integer()) :: {:ok, map()} | {:error, :not_in_queue}
  def get_queue_status(player_guid) do
    GenServer.call(__MODULE__, {:get_queue_status, player_guid})
  end

  @doc """
  Player confirms ready for match.
  """
  @spec confirm_ready(non_neg_integer()) :: :ok | {:error, atom()}
  def confirm_ready(player_guid) do
    GenServer.call(__MODULE__, {:confirm_ready, player_guid})
  end

  @doc """
  Get all available battlegrounds.
  """
  @spec list_battlegrounds() :: [map()]
  def list_battlegrounds do
    Store.get_all_battlegrounds()
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("BattlegroundQueue started")

    # Schedule periodic queue pop check
    schedule_queue_check()

    # Initialize queues for each battleground
    battlegrounds = Store.get_all_battlegrounds()

    queues =
      Enum.reduce(battlegrounds, %{}, fn bg, acc ->
        Map.put(acc, bg.id, %{exile: [], dominion: []})
      end)

    state = %{
      queues: queues,
      player_queues: %{},
      active_instances: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:join_queue, player_guid, player_name, faction, level, class_id, battleground_id},
        _from,
        state
      ) do
    cond do
      Map.has_key?(state.player_queues, player_guid) ->
        {:reply, {:error, :already_in_queue}, state}

      not Map.has_key?(state.queues, battleground_id) ->
        {:reply, {:error, :invalid_battleground}, state}

      true ->
        entry = %__MODULE__{
          player_guid: player_guid,
          player_name: player_name,
          faction: faction,
          level: level,
          class_id: class_id,
          queued_at: System.monotonic_time(:millisecond)
        }

        # Add to faction queue
        queues = state.queues
        bg_queues = Map.get(queues, battleground_id)
        faction_queue = Map.get(bg_queues, faction)
        updated_faction_queue = faction_queue ++ [entry]

        bg_queues = Map.put(bg_queues, faction, updated_faction_queue)
        queues = Map.put(queues, battleground_id, bg_queues)

        # Set timeout for queue
        timer_ref = Process.send_after(self(), {:queue_timeout, player_guid}, @max_queue_time_ms)
        player_queues = Map.put(state.player_queues, player_guid, {battleground_id, timer_ref})

        state = %{state | queues: queues, player_queues: player_queues}

        # Estimate wait time based on queue sizes
        estimated_wait = estimate_wait_time(state, battleground_id, faction)

        Logger.debug("Player #{player_name} joined BG #{battleground_id} queue (#{faction})")
        {:reply, {:ok, estimated_wait}, state}
    end
  end

  def handle_call({:leave_queue, player_guid}, _from, state) do
    case Map.get(state.player_queues, player_guid) do
      nil ->
        {:reply, {:error, :not_in_queue}, state}

      {battleground_id, timer_ref} ->
        Process.cancel_timer(timer_ref)
        state = remove_from_queue(state, player_guid, battleground_id)
        {:reply, :ok, state}
    end
  end

  def handle_call({:in_queue?, player_guid}, _from, state) do
    in_queue = Map.has_key?(state.player_queues, player_guid)
    {:reply, in_queue, state}
  end

  def handle_call({:get_queue_status, player_guid}, _from, state) do
    case Map.get(state.player_queues, player_guid) do
      nil ->
        {:reply, {:error, :not_in_queue}, state}

      {battleground_id, _timer_ref} ->
        bg_queues = Map.get(state.queues, battleground_id)
        entry = find_entry(bg_queues, player_guid)

        if entry do
          now = System.monotonic_time(:millisecond)
          wait_time = div(now - entry.queued_at, 1000)

          status = %{
            battleground_id: battleground_id,
            faction: entry.faction,
            wait_time_seconds: wait_time,
            estimated_wait: estimate_wait_time(state, battleground_id, entry.faction),
            position: queue_position(bg_queues, entry.faction, player_guid)
          }

          {:reply, {:ok, status}, state}
        else
          {:reply, {:error, :not_in_queue}, state}
        end
    end
  end

  def handle_call({:confirm_ready, _player_guid}, _from, state) do
    # Ready check implementation - for now just acknowledge
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:check_queues, state) do
    state = check_and_pop_queues(state)
    schedule_queue_check()
    {:noreply, state}
  end

  def handle_info({:queue_timeout, player_guid}, state) do
    case Map.get(state.player_queues, player_guid) do
      nil ->
        {:noreply, state}

      {battleground_id, _timer_ref} ->
        Logger.debug("Player #{player_guid} queue timeout")
        state = remove_from_queue(state, player_guid, battleground_id)
        {:noreply, state}
    end
  end

  # Private functions

  defp schedule_queue_check do
    Process.send_after(self(), :check_queues, @queue_pop_check_interval)
  end

  defp check_and_pop_queues(state) do
    Enum.reduce(state.queues, state, fn {bg_id, bg_queues}, acc_state ->
      check_and_pop_battleground(acc_state, bg_id, bg_queues)
    end)
  end

  defp check_and_pop_battleground(state, battleground_id, bg_queues) do
    exile_queue = Map.get(bg_queues, :exile, [])
    dominion_queue = Map.get(bg_queues, :dominion, [])

    exile_count = length(exile_queue)
    dominion_count = length(dominion_queue)

    # Check if we have enough players on both sides
    if exile_count >= @min_players_per_team and dominion_count >= @min_players_per_team do
      # Pop teams for the match
      team_size = min(@max_players_per_team, min(exile_count, dominion_count))

      {exile_team, remaining_exile} = Enum.split(exile_queue, team_size)
      {dominion_team, remaining_dominion} = Enum.split(dominion_queue, team_size)

      # Create the match
      match_id = create_battleground_match(battleground_id, exile_team, dominion_team)

      Logger.info(
        "Created BG match #{match_id} for BG #{battleground_id} (#{team_size}v#{team_size})"
      )

      # Update queues
      bg_queues = %{exile: remaining_exile, dominion: remaining_dominion}
      queues = Map.put(state.queues, battleground_id, bg_queues)

      # Remove players from tracking
      all_players = exile_team ++ dominion_team

      player_queues =
        Enum.reduce(all_players, state.player_queues, fn entry, acc ->
          case Map.get(acc, entry.player_guid) do
            {_, timer_ref} ->
              Process.cancel_timer(timer_ref)
              Map.delete(acc, entry.player_guid)

            nil ->
              acc
          end
        end)

      # Track active instance
      active_instances = MapSet.put(state.active_instances, match_id)

      %{state | queues: queues, player_queues: player_queues, active_instances: active_instances}
    else
      state
    end
  end

  defp create_battleground_match(battleground_id, exile_team, dominion_team) do
    match_id = generate_match_id()

    # Start the battleground instance
    case BezgelorWorld.PvP.BattlegroundInstance.start_instance(
           match_id,
           battleground_id,
           exile_team,
           dominion_team
         ) do
      {:ok, _pid} ->
        match_id

      {:error, reason} ->
        Logger.error("Failed to start BG instance: #{inspect(reason)}")
        match_id
    end
  end

  defp remove_from_queue(state, player_guid, battleground_id) do
    bg_queues = Map.get(state.queues, battleground_id)

    # Remove from faction queues
    exile_queue = Enum.reject(bg_queues.exile, fn e -> e.player_guid == player_guid end)
    dominion_queue = Enum.reject(bg_queues.dominion, fn e -> e.player_guid == player_guid end)

    bg_queues = %{exile: exile_queue, dominion: dominion_queue}
    queues = Map.put(state.queues, battleground_id, bg_queues)

    player_queues = Map.delete(state.player_queues, player_guid)

    %{state | queues: queues, player_queues: player_queues}
  end

  defp find_entry(bg_queues, player_guid) do
    Enum.find(bg_queues.exile ++ bg_queues.dominion, fn e ->
      e.player_guid == player_guid
    end)
  end

  defp queue_position(bg_queues, faction, player_guid) do
    queue = Map.get(bg_queues, faction, [])

    case Enum.find_index(queue, fn e -> e.player_guid == player_guid end) do
      nil -> 0
      idx -> idx + 1
    end
  end

  defp estimate_wait_time(state, battleground_id, faction) do
    bg_queues = Map.get(state.queues, battleground_id, %{exile: [], dominion: []})
    own_queue = Map.get(bg_queues, faction, [])
    opposite_faction = if faction == :exile, do: :dominion, else: :exile
    opposite_queue = Map.get(bg_queues, opposite_faction, [])

    own_count = length(own_queue)
    opposite_count = length(opposite_queue)

    cond do
      own_count >= @min_players_per_team and opposite_count >= @min_players_per_team ->
        # Should pop soon
        5

      opposite_count < @min_players_per_team ->
        # Waiting on opposite faction
        needed = @min_players_per_team - opposite_count
        # Rough estimate: 30 seconds per player needed
        needed * 30

      true ->
        # Waiting in queue
        position = own_count - @min_players_per_team + 1
        max(0, position * 60)
    end
  end

  defp generate_match_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
