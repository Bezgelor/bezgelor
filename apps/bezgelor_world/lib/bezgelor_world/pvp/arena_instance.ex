defmodule BezgelorWorld.PvP.ArenaInstance do
  @moduledoc """
  Manages a single arena match.

  State machine:
    PREPARATION (30s) -> ACTIVE -> ENDING (10s) -> COMPLETE

  Features:
  - Team-based combat (2v2, 3v3, 5v5)
  - Dampening system (healing reduction over time)
  - Rating calculations at match end
  """

  use GenServer

  require Logger

  alias BezgelorDb.{ArenaTeams, PvP}
  alias BezgelorData.Store

  # Timing
  @preparation_time_ms 30_000
  @round_time_limit_ms 600_000
  @dampening_start_ms 300_000
  @dampening_tick_ms 10_000
  @dampening_per_tick 1
  @ending_time_ms 10_000

  @match_state_preparation :preparation
  @match_state_active :active
  @match_state_ending :ending
  @match_state_complete :complete

  defstruct [
    :match_id,
    :bracket,
    :arena_id,
    :match_state,
    :team1,
    :team2,
    :team1_alive,
    :team2_alive,
    :round_number,
    :dampening_percent,
    :started_at,
    :winner,
    :rating_changes
  ]

  @type match_state :: :preparation | :active | :ending | :complete

  @type team_state :: %{
          team_id: integer(),
          name: String.t(),
          members: [
            %{
              guid: non_neg_integer(),
              alive: boolean(),
              damage_done: non_neg_integer(),
              healing_done: non_neg_integer(),
              kills: non_neg_integer()
            }
          ],
          rating: non_neg_integer()
        }

  @type t :: %__MODULE__{
          match_id: String.t(),
          bracket: String.t(),
          arena_id: non_neg_integer(),
          match_state: match_state(),
          team1: team_state(),
          team2: team_state(),
          team1_alive: non_neg_integer(),
          team2_alive: non_neg_integer(),
          round_number: non_neg_integer(),
          dampening_percent: non_neg_integer(),
          started_at: DateTime.t() | nil,
          winner: :team1 | :team2 | nil,
          rating_changes: map() | nil
        }

  # Client API

  @doc """
  Start a new arena instance.
  """
  @spec start_instance(String.t(), String.t(), map(), map()) :: {:ok, pid()} | {:error, term()}
  def start_instance(match_id, bracket, team1_entry, team2_entry) do
    DynamicSupervisor.start_child(
      BezgelorWorld.PvP.ArenaSupervisor,
      {__MODULE__, [match_id, bracket, team1_entry, team2_entry]}
    )
  end

  def start_link([match_id, bracket, team1_entry, team2_entry]) do
    GenServer.start_link(__MODULE__, [match_id, bracket, team1_entry, team2_entry],
      name: via_tuple(match_id)
    )
  end

  defp via_tuple(match_id) do
    {:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, match_id}}
  end

  @doc """
  Report a player death.
  """
  @spec report_death(String.t(), non_neg_integer()) :: :ok | {:error, atom()}
  def report_death(match_id, player_guid) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:report_death, player_guid})
    end
  end

  @doc """
  Report damage done by a player.
  """
  @spec report_damage(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def report_damage(match_id, player_guid, amount) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:report_damage, player_guid, amount})
    end
  end

  @doc """
  Report healing done by a player.
  """
  @spec report_healing(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def report_healing(match_id, player_guid, amount) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:report_healing, player_guid, amount})
    end
  end

  @doc """
  Get the current match state.
  """
  @spec get_state(String.t()) :: t() | {:error, :not_found}
  def get_state(match_id) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  @doc """
  Get current dampening percentage.
  """
  @spec get_dampening(String.t()) :: non_neg_integer() | {:error, :not_found}
  def get_dampening(match_id) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_dampening)
    end
  end

  # Server callbacks

  @impl true
  def init([match_id, bracket, team1_entry, team2_entry]) do
    Logger.info("Starting arena #{bracket} match #{match_id}")

    team_size = bracket_size(bracket)

    state = %__MODULE__{
      match_id: match_id,
      bracket: bracket,
      arena_id: select_arena(bracket),
      match_state: @match_state_preparation,
      team1: build_team_state(team1_entry),
      team2: build_team_state(team2_entry),
      team1_alive: team_size,
      team2_alive: team_size,
      round_number: 1,
      dampening_percent: 0,
      started_at: nil,
      winner: nil,
      rating_changes: nil
    }

    Process.send_after(self(), :preparation_complete, @preparation_time_ms)

    {:ok, state}
  end

  @impl true
  def handle_call({:report_death, player_guid}, _from, state) do
    if state.match_state == @match_state_active do
      state = process_death(state, player_guid)
      state = check_victory(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_dampening, _from, state) do
    {:reply, state.dampening_percent, state}
  end

  @impl true
  def handle_cast({:report_damage, player_guid, amount}, state) do
    state = update_player_stat(state, player_guid, :damage_done, amount)
    {:noreply, state}
  end

  def handle_cast({:report_healing, player_guid, amount}, state) do
    state = update_player_stat(state, player_guid, :healing_done, amount)
    {:noreply, state}
  end

  @impl true
  def handle_info(:preparation_complete, state) do
    if state.match_state == @match_state_preparation do
      Logger.info("Arena #{state.match_id} starting!")

      state = %{
        state
        | match_state: @match_state_active,
          started_at: DateTime.utc_now()
      }

      # Schedule dampening check
      Process.send_after(self(), :dampening_tick, @dampening_start_ms)

      # Schedule round time limit
      Process.send_after(self(), :round_time_limit, @round_time_limit_ms)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:dampening_tick, state) do
    if state.match_state == @match_state_active do
      new_dampening = min(100, state.dampening_percent + @dampening_per_tick)

      Logger.debug("Arena #{state.match_id} dampening now at #{new_dampening}%")

      state = %{state | dampening_percent: new_dampening}

      # Continue dampening ticks
      if new_dampening < 100 do
        Process.send_after(self(), :dampening_tick, @dampening_tick_ms)
      end

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:round_time_limit, state) do
    if state.match_state == @match_state_active do
      # Determine winner by remaining health percentage
      state = end_match_by_health(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:ending_complete, state) do
    if state.match_state == @match_state_ending do
      # Calculate and apply rating changes
      rating_changes = calculate_rating_changes(state)
      apply_rating_changes(state, rating_changes)

      state = %{
        state
        | match_state: @match_state_complete,
          rating_changes: rating_changes
      }

      # Cleanup after delay
      Process.send_after(self(), :cleanup, 60_000)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:cleanup, state) do
    Logger.info("Cleaning up arena #{state.match_id}")
    {:stop, :normal, state}
  end

  # Private functions

  defp bracket_size("2v2"), do: 2
  defp bracket_size("3v3"), do: 3
  defp bracket_size("5v5"), do: 5
  defp bracket_size(_), do: 2

  defp select_arena(bracket) do
    arenas = Store.get_all_arenas()

    case arenas do
      [] ->
        1

      _ ->
        valid_arenas =
          Enum.filter(arenas, fn a ->
            bracket in Map.get(a, :brackets, []) or "all" in Map.get(a, :brackets, [])
          end)

        case valid_arenas do
          [] -> 1
          list -> Enum.random(list).id
        end
    end
  end

  defp build_team_state(entry) do
    members =
      Enum.map(entry.members, fn guid ->
        %{guid: guid, alive: true, damage_done: 0, healing_done: 0, kills: 0}
      end)

    %{
      team_id: entry.team_id,
      name: entry.team_name,
      members: members,
      rating: entry.rating
    }
  end

  defp process_death(state, player_guid) do
    cond do
      player_in_team?(state.team1, player_guid) ->
        team1 = mark_dead(state.team1, player_guid)
        %{state | team1: team1, team1_alive: count_alive(team1)}

      player_in_team?(state.team2, player_guid) ->
        team2 = mark_dead(state.team2, player_guid)
        %{state | team2: team2, team2_alive: count_alive(team2)}

      true ->
        state
    end
  end

  defp player_in_team?(team, guid) do
    Enum.any?(team.members, fn m -> m.guid == guid end)
  end

  defp mark_dead(team, guid) do
    members =
      Enum.map(team.members, fn m ->
        if m.guid == guid, do: %{m | alive: false}, else: m
      end)

    %{team | members: members}
  end

  defp count_alive(team) do
    Enum.count(team.members, fn m -> m.alive end)
  end

  defp update_player_stat(state, player_guid, stat, amount) do
    update_team = fn team ->
      members =
        Enum.map(team.members, fn m ->
          if m.guid == player_guid do
            Map.update!(m, stat, &(&1 + amount))
          else
            m
          end
        end)

      %{team | members: members}
    end

    %{state | team1: update_team.(state.team1), team2: update_team.(state.team2)}
  end

  defp check_victory(state) do
    cond do
      state.team1_alive == 0 ->
        end_match(state, :team2)

      state.team2_alive == 0 ->
        end_match(state, :team1)

      true ->
        state
    end
  end

  defp end_match(state, winner) do
    Logger.info("Arena #{state.match_id} ended - Winner: #{winner}")

    state = %{
      state
      | match_state: @match_state_ending,
        winner: winner
    }

    Process.send_after(self(), :ending_complete, @ending_time_ms)

    state
  end

  defp end_match_by_health(state) do
    # For now, team with more alive wins
    # TODO: Calculate by remaining health percentage
    winner = if state.team1_alive > state.team2_alive, do: :team1, else: :team2
    end_match(state, winner)
  end

  defp calculate_rating_changes(state) do
    winner_team = if state.winner == :team1, do: state.team1, else: state.team2
    loser_team = if state.winner == :team1, do: state.team2, else: state.team1

    {winner_gain, loser_loss} =
      BezgelorWorld.PvP.Rating.calculate_elo_change(
        winner_team.rating,
        loser_team.rating
      )

    %{
      winner: %{
        team_id: winner_team.team_id,
        old_rating: winner_team.rating,
        new_rating: winner_team.rating + winner_gain,
        change: winner_gain
      },
      loser: %{
        team_id: loser_team.team_id,
        old_rating: loser_team.rating,
        new_rating: max(0, loser_team.rating - loser_loss),
        change: -loser_loss
      }
    }
  end

  defp apply_rating_changes(state, changes) do
    spawn(fn ->
      winner_team = if state.winner == :team1, do: state.team1, else: state.team2
      loser_team = if state.winner == :team1, do: state.team2, else: state.team1

      winner_participant_ids = Enum.map(winner_team.members, & &1.guid)
      loser_participant_ids = Enum.map(loser_team.members, & &1.guid)

      # Record team match results (only for registered teams, not ad-hoc)
      if changes.winner.team_id > 0 do
        ArenaTeams.record_match(
          changes.winner.team_id,
          true,
          changes.winner.change,
          winner_participant_ids
        )
      end

      if changes.loser.team_id > 0 do
        ArenaTeams.record_match(
          changes.loser.team_id,
          false,
          changes.loser.change,
          loser_participant_ids
        )
      end

      # Also update individual player ratings via BezgelorDb.PvP
      bracket = state.bracket

      Enum.each(winner_participant_ids, fn char_id ->
        PvP.record_match(char_id, bracket, true, changes.loser.old_rating)
        PvP.record_arena(char_id, true)
      end)

      Enum.each(loser_participant_ids, fn char_id ->
        PvP.record_match(char_id, bracket, false, changes.winner.old_rating)
        PvP.record_arena(char_id, false)
      end)
    end)
  end
end
