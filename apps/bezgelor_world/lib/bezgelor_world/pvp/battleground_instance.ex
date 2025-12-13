defmodule BezgelorWorld.PvP.BattlegroundInstance do
  @moduledoc """
  Manages a single battleground instance.

  Handles:
  - Match lifecycle (preparation, active, ending)
  - Score tracking
  - Objectives (flags, capture points, etc.)
  - Victory conditions
  - Player spawning and respawning
  """

  use GenServer

  require Logger

  alias BezgelorData.Store
  alias BezgelorDb.PvP

  # Match timing
  @preparation_time_ms 60_000
  @match_duration_ms 1_200_000
  @ending_time_ms 15_000

  # Victory conditions
  @default_score_limit 1600
  @capture_point_score_per_tick 10
  @flag_capture_score 100
  @kill_score 5

  @match_state_preparation :preparation
  @match_state_active :active
  @match_state_ending :ending
  @match_state_complete :complete

  defstruct [
    :match_id,
    :battleground_id,
    :battleground_data,
    :match_state,
    :exile_team,
    :dominion_team,
    :exile_score,
    :dominion_score,
    :score_limit,
    :objectives,
    :started_at,
    :ends_at,
    :winner
  ]

  @type team_entry :: %{
          player_guid: non_neg_integer(),
          player_name: String.t(),
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          assists: non_neg_integer(),
          damage_done: non_neg_integer(),
          healing_done: non_neg_integer(),
          objectives: non_neg_integer()
        }

  @type objective :: %{
          id: non_neg_integer(),
          type: :flag | :capture_point | :payload,
          owner: :exile | :dominion | :neutral,
          progress: float(),
          position: {float(), float(), float()}
        }

  @type t :: %__MODULE__{
          match_id: String.t(),
          battleground_id: non_neg_integer(),
          battleground_data: map(),
          match_state: :preparation | :active | :ending | :complete,
          exile_team: [team_entry()],
          dominion_team: [team_entry()],
          exile_score: non_neg_integer(),
          dominion_score: non_neg_integer(),
          score_limit: non_neg_integer(),
          objectives: [objective()],
          started_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          winner: :exile | :dominion | :draw | nil
        }

  # Client API

  @doc """
  Start a new battleground instance.
  """
  @spec start_instance(String.t(), non_neg_integer(), [map()], [map()]) ::
          {:ok, pid()} | {:error, term()}
  def start_instance(match_id, battleground_id, exile_team, dominion_team) do
    DynamicSupervisor.start_child(
      BezgelorWorld.PvP.BattlegroundSupervisor,
      {__MODULE__, [match_id, battleground_id, exile_team, dominion_team]}
    )
  end

  def start_link([match_id, battleground_id, exile_team, dominion_team]) do
    GenServer.start_link(__MODULE__, [match_id, battleground_id, exile_team, dominion_team],
      name: via_tuple(match_id)
    )
  end

  defp via_tuple(match_id) do
    {:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, match_id}}
  end

  @doc """
  Get the current match state.
  """
  @spec get_state(String.t()) :: {:ok, t()} | {:error, :not_found}
  def get_state(match_id) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> {:ok, GenServer.call(pid, :get_state)}
    end
  end

  @doc """
  Report a player kill.
  """
  @spec report_kill(String.t(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, atom()}
  def report_kill(match_id, killer_guid, victim_guid) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:report_kill, killer_guid, victim_guid})
    end
  end

  @doc """
  Report objective interaction (flag pickup, capture point progress, etc.).
  """
  @spec interact_objective(String.t(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, atom()}
  def interact_objective(match_id, player_guid, objective_id) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:interact_objective, player_guid, objective_id})
    end
  end

  @doc """
  Player leaves the battleground.
  """
  @spec player_leave(String.t(), non_neg_integer()) :: :ok
  def player_leave(match_id, player_guid) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:player_leave, player_guid})
    end
  end

  # Server callbacks

  @impl true
  def init([match_id, battleground_id, exile_team_raw, dominion_team_raw]) do
    Logger.info("Starting battleground instance #{match_id} for BG #{battleground_id}")

    # Get battleground data
    bg_data =
      case Store.get_battleground(battleground_id) do
        {:ok, data} -> data
        :error -> %{name: "Unknown", score_limit: @default_score_limit, type: "capture"}
      end

    # Initialize team entries with stats
    exile_team = Enum.map(exile_team_raw, &initialize_team_entry/1)
    dominion_team = Enum.map(dominion_team_raw, &initialize_team_entry/1)

    # Initialize objectives based on battleground type
    objectives = initialize_objectives(bg_data)

    state = %__MODULE__{
      match_id: match_id,
      battleground_id: battleground_id,
      battleground_data: bg_data,
      match_state: @match_state_preparation,
      exile_team: exile_team,
      dominion_team: dominion_team,
      exile_score: 0,
      dominion_score: 0,
      score_limit: Map.get(bg_data, :score_limit, @default_score_limit),
      objectives: objectives,
      started_at: nil,
      ends_at: nil,
      winner: nil
    }

    # Start preparation timer
    Process.send_after(self(), :preparation_complete, @preparation_time_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:report_kill, killer_guid, victim_guid}, _from, state) do
    if state.match_state == @match_state_active do
      state = process_kill(state, killer_guid, victim_guid)
      state = check_victory(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  def handle_call({:interact_objective, player_guid, objective_id}, _from, state) do
    if state.match_state == @match_state_active do
      case process_objective_interaction(state, player_guid, objective_id) do
        {:ok, state} ->
          state = check_victory(state)
          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  @impl true
  def handle_cast({:player_leave, player_guid}, state) do
    # Mark player as left but keep their stats
    state = mark_player_left(state, player_guid)
    {:noreply, state}
  end

  @impl true
  def handle_info(:preparation_complete, state) do
    if state.match_state == @match_state_preparation do
      Logger.info("Battleground #{state.match_id} starting!")

      now = DateTime.utc_now()
      ends_at = DateTime.add(now, div(@match_duration_ms, 1000), :second)

      state = %{state |
        match_state: @match_state_active,
        started_at: now,
        ends_at: ends_at
      }

      # Schedule match end
      Process.send_after(self(), :match_time_expired, @match_duration_ms)

      # Start objective tick if applicable
      schedule_objective_tick(state)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:match_time_expired, state) do
    if state.match_state == @match_state_active do
      state = end_match(state, :time_expired)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:ending_complete, state) do
    if state.match_state == @match_state_ending do
      Logger.info("Battleground #{state.match_id} complete - Winner: #{state.winner}")

      # Record stats
      record_match_results(state)

      state = %{state | match_state: @match_state_complete}

      # Schedule cleanup
      Process.send_after(self(), :cleanup, 60_000)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:objective_tick, state) do
    if state.match_state == @match_state_active do
      state = process_objective_tick(state)
      state = check_victory(state)

      if state.match_state == @match_state_active do
        schedule_objective_tick(state)
      end

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:cleanup, state) do
    Logger.info("Cleaning up battleground #{state.match_id}")
    {:stop, :normal, state}
  end

  # Private functions

  defp initialize_team_entry(entry) do
    %{
      player_guid: entry.player_guid,
      player_name: entry.player_name,
      faction: entry.faction,
      kills: 0,
      deaths: 0,
      assists: 0,
      damage_done: 0,
      healing_done: 0,
      objectives: 0,
      active: true
    }
  end

  defp initialize_objectives(bg_data) do
    type = Map.get(bg_data, :type, "capture")

    case type do
      "capture" ->
        # Capture the flag style (Walatiki Temple)
        [
          %{id: 1, type: :flag, owner: :neutral, progress: 0.0, position: {0.0, 0.0, 0.0}, carrier: nil},
          %{id: 2, type: :capture_point, owner: :exile, progress: 1.0, position: {-100.0, 0.0, 0.0}},
          %{id: 3, type: :capture_point, owner: :dominion, progress: 1.0, position: {100.0, 0.0, 0.0}}
        ]

      "control" ->
        # Control points (Halls of the Bloodsworn)
        [
          %{id: 1, type: :capture_point, owner: :neutral, progress: 0.5, position: {0.0, 0.0, 0.0}},
          %{id: 2, type: :capture_point, owner: :neutral, progress: 0.5, position: {-50.0, 0.0, 50.0}},
          %{id: 3, type: :capture_point, owner: :neutral, progress: 0.5, position: {50.0, 0.0, 50.0}}
        ]

      _ ->
        []
    end
  end

  defp process_kill(state, killer_guid, victim_guid) do
    killer_faction = get_player_faction(state, killer_guid)
    victim_faction = get_player_faction(state, victim_guid)

    # Update killer stats
    state = update_player_stat(state, killer_guid, :kills, 1)

    # Update victim stats
    state = update_player_stat(state, victim_guid, :deaths, 1)

    # Award score for kill
    if killer_faction && killer_faction != victim_faction do
      add_score(state, killer_faction, @kill_score)
    else
      state
    end
  end

  defp process_objective_interaction(state, player_guid, objective_id) do
    objective = Enum.find(state.objectives, fn o -> o.id == objective_id end)
    player_faction = get_player_faction(state, player_guid)

    cond do
      is_nil(objective) ->
        {:error, :invalid_objective}

      is_nil(player_faction) ->
        {:error, :player_not_in_match}

      objective.type == :flag and objective.owner == :neutral ->
        # Pick up flag
        objectives =
          Enum.map(state.objectives, fn o ->
            if o.id == objective_id do
              %{o | carrier: player_guid}
            else
              o
            end
          end)

        {:ok, %{state | objectives: objectives}}

      objective.type == :flag and objective.carrier == player_guid ->
        # Capture flag at base
        base = Enum.find(state.objectives, fn o ->
          o.type == :capture_point and o.owner == player_faction
        end)

        if base do
          # Score and reset flag
          state = add_score(state, player_faction, @flag_capture_score)
          state = update_player_stat(state, player_guid, :objectives, 1)

          objectives =
            Enum.map(state.objectives, fn o ->
              if o.id == objective_id do
                %{o | owner: :neutral, carrier: nil}
              else
                o
              end
            end)

          {:ok, %{state | objectives: objectives}}
        else
          {:error, :no_capture_point}
        end

      objective.type == :capture_point ->
        # Progress capture
        progress_delta = if player_faction == :exile, do: 0.1, else: -0.1
        new_progress = max(0.0, min(1.0, objective.progress + progress_delta))

        new_owner =
          cond do
            new_progress >= 1.0 -> :exile
            new_progress <= 0.0 -> :dominion
            true -> objective.owner
          end

        objectives =
          Enum.map(state.objectives, fn o ->
            if o.id == objective_id do
              %{o | progress: new_progress, owner: new_owner}
            else
              o
            end
          end)

        {:ok, %{state | objectives: objectives}}

      true ->
        {:error, :invalid_interaction}
    end
  end

  defp process_objective_tick(state) do
    # Award score for controlled points
    exile_points = count_controlled_points(state.objectives, :exile)
    dominion_points = count_controlled_points(state.objectives, :dominion)

    state = add_score(state, :exile, exile_points * @capture_point_score_per_tick)
    add_score(state, :dominion, dominion_points * @capture_point_score_per_tick)
  end

  defp count_controlled_points(objectives, faction) do
    Enum.count(objectives, fn o ->
      o.type == :capture_point and o.owner == faction
    end)
  end

  defp schedule_objective_tick(_state) do
    # Tick every 5 seconds for capture point scoring
    Process.send_after(self(), :objective_tick, 5_000)
  end

  defp get_player_faction(state, player_guid) do
    cond do
      Enum.any?(state.exile_team, fn p -> p.player_guid == player_guid end) -> :exile
      Enum.any?(state.dominion_team, fn p -> p.player_guid == player_guid end) -> :dominion
      true -> nil
    end
  end

  defp update_player_stat(state, player_guid, stat, delta) do
    update_team_fn = fn team ->
      Enum.map(team, fn p ->
        if p.player_guid == player_guid do
          Map.update!(p, stat, &(&1 + delta))
        else
          p
        end
      end)
    end

    %{state |
      exile_team: update_team_fn.(state.exile_team),
      dominion_team: update_team_fn.(state.dominion_team)
    }
  end

  defp add_score(state, :exile, amount) do
    %{state | exile_score: state.exile_score + amount}
  end

  defp add_score(state, :dominion, amount) do
    %{state | dominion_score: state.dominion_score + amount}
  end

  defp add_score(state, _, _), do: state

  defp mark_player_left(state, player_guid) do
    update_team_fn = fn team ->
      Enum.map(team, fn p ->
        if p.player_guid == player_guid do
          Map.put(p, :active, false)
        else
          p
        end
      end)
    end

    %{state |
      exile_team: update_team_fn.(state.exile_team),
      dominion_team: update_team_fn.(state.dominion_team)
    }
  end

  defp check_victory(state) do
    cond do
      state.exile_score >= state.score_limit ->
        end_match(state, :exile_victory)

      state.dominion_score >= state.score_limit ->
        end_match(state, :dominion_victory)

      true ->
        state
    end
  end

  defp end_match(state, reason) do
    winner =
      case reason do
        :exile_victory -> :exile
        :dominion_victory -> :dominion
        :time_expired ->
          cond do
            state.exile_score > state.dominion_score -> :exile
            state.dominion_score > state.exile_score -> :dominion
            true -> :draw
          end
      end

    Logger.info("Battleground #{state.match_id} ending - #{reason}")

    state = %{state |
      match_state: @match_state_ending,
      winner: winner
    }

    Process.send_after(self(), :ending_complete, @ending_time_ms)

    state
  end

  defp record_match_results(state) do
    # Record stats for all players
    all_players = state.exile_team ++ state.dominion_team

    spawn(fn ->
      Enum.each(all_players, fn player ->
        won = (player.faction == state.winner)

        # TODO: Add kills/deaths tracking to record_battleground
        PvP.record_battleground(player.player_guid, won)
      end)
    end)
  rescue
    error ->
      Logger.warning("Failed to record BG results: #{inspect(error)}")
  end
end
