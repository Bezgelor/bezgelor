defmodule BezgelorWorld.PvP.WarplotInstance do
  @moduledoc """
  Manages a single warplot battle instance.

  Warplots are 40v40 guild-vs-guild battles with:
  - Generator objectives (primary win condition)
  - Boss kill objectives (secondary)
  - Resource control (tertiary)
  - Plug-based defenses
  """

  use GenServer

  require Logger

  alias BezgelorDb.Warplots

  # Timing
  @preparation_time_ms 120_000
  @match_duration_ms 2_400_000
  @ending_time_ms 30_000
  @score_tick_interval_ms 5_000

  # Victory conditions
  @generator_health 500_000
  @boss_kill_points 1000
  @resource_points_per_tick 10
  @score_to_win 5000

  @match_state_preparation :preparation
  @match_state_active :active
  @match_state_ending :ending
  @match_state_complete :complete

  defstruct [
    :match_id,
    :match_state,
    :team1,
    :team2,
    :team1_score,
    :team2_score,
    :team1_generator_health,
    :team2_generator_health,
    :team1_boss_alive,
    :team2_boss_alive,
    :resource_nodes,
    :started_at,
    :ends_at,
    :winner
  ]

  @type match_state :: :preparation | :active | :ending | :complete

  @type team :: %{
          guild_id: non_neg_integer(),
          warplot: map(),
          members: [non_neg_integer()],
          kills: non_neg_integer(),
          deaths: non_neg_integer()
        }

  @type t :: %__MODULE__{
          match_id: String.t(),
          match_state: match_state(),
          team1: team(),
          team2: team(),
          team1_score: non_neg_integer(),
          team2_score: non_neg_integer(),
          team1_generator_health: non_neg_integer(),
          team2_generator_health: non_neg_integer(),
          team1_boss_alive: boolean(),
          team2_boss_alive: boolean(),
          resource_nodes: map(),
          started_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          winner: :team1 | :team2 | :draw | nil
        }

  # Client API

  @doc """
  Start a new warplot battle instance.
  """
  @spec start_instance(String.t(), map(), map()) :: {:ok, pid()} | {:error, term()}
  def start_instance(match_id, warplot1, warplot2) do
    DynamicSupervisor.start_child(
      BezgelorWorld.PvP.WarplotSupervisor,
      {__MODULE__, [match_id, warplot1, warplot2]}
    )
  end

  def start_link([match_id, warplot1, warplot2]) do
    GenServer.start_link(__MODULE__, [match_id, warplot1, warplot2], name: via_tuple(match_id))
  end

  defp via_tuple(match_id) do
    {:via, Registry, {BezgelorWorld.PvP.WarplotRegistry, match_id}}
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
  Report damage to a generator.
  """
  @spec damage_generator(String.t(), :team1 | :team2, non_neg_integer()) :: :ok | {:error, atom()}
  def damage_generator(match_id, team, amount) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:damage_generator, team, amount})
    end
  end

  @doc """
  Report a boss kill.
  """
  @spec boss_killed(String.t(), :team1 | :team2) :: :ok | {:error, atom()}
  def boss_killed(match_id, team) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:boss_killed, team})
    end
  end

  @doc """
  Capture a resource node.
  """
  @spec capture_resource(String.t(), non_neg_integer(), :team1 | :team2) :: :ok | {:error, atom()}
  def capture_resource(match_id, node_id, team) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:capture_resource, node_id, team})
    end
  end

  @doc """
  Report a player kill.
  """
  @spec report_kill(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def report_kill(match_id, killer_guid, victim_guid) do
    case GenServer.whereis(via_tuple(match_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:report_kill, killer_guid, victim_guid})
    end
  end

  # Server callbacks

  @impl true
  def init([match_id, warplot1, warplot2]) do
    Logger.info("Starting warplot battle #{match_id}")

    resource_nodes = initialize_resource_nodes()

    state = %__MODULE__{
      match_id: match_id,
      match_state: @match_state_preparation,
      team1: build_team_state(warplot1),
      team2: build_team_state(warplot2),
      team1_score: 0,
      team2_score: 0,
      team1_generator_health: @generator_health,
      team2_generator_health: @generator_health,
      team1_boss_alive: true,
      team2_boss_alive: true,
      resource_nodes: resource_nodes,
      started_at: nil,
      ends_at: nil,
      winner: nil
    }

    Process.send_after(self(), :preparation_complete, @preparation_time_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:damage_generator, team, amount}, _from, state) do
    if state.match_state == @match_state_active do
      state = apply_generator_damage(state, team, amount)
      state = check_victory(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  def handle_call({:boss_killed, team}, _from, state) do
    if state.match_state == @match_state_active do
      state = process_boss_kill(state, team)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  def handle_call({:capture_resource, node_id, team}, _from, state) do
    if state.match_state == @match_state_active do
      state = capture_node(state, node_id, team)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  @impl true
  def handle_cast({:report_kill, killer_guid, victim_guid}, state) do
    state = process_kill(state, killer_guid, victim_guid)
    {:noreply, state}
  end

  @impl true
  def handle_info(:preparation_complete, state) do
    if state.match_state == @match_state_preparation do
      Logger.info("Warplot #{state.match_id} starting!")

      now = DateTime.utc_now()
      ends_at = DateTime.add(now, div(@match_duration_ms, 1000), :second)

      state = %{
        state
        | match_state: @match_state_active,
          started_at: now,
          ends_at: ends_at
      }

      Process.send_after(self(), :match_time_expired, @match_duration_ms)
      schedule_score_tick()

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:score_tick, state) do
    if state.match_state == @match_state_active do
      state = process_score_tick(state)
      state = check_victory(state)

      if state.match_state == @match_state_active do
        schedule_score_tick()
      end

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
      Logger.info("Warplot #{state.match_id} complete - Winner: #{state.winner}")

      # Record results and distribute rewards
      record_match_results(state)

      state = %{state | match_state: @match_state_complete}

      # Notify manager
      send(BezgelorWorld.PvP.WarplotManager, {:battle_complete, state.match_id})

      # Cleanup after delay
      Process.send_after(self(), :cleanup, 60_000)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:cleanup, state) do
    Logger.info("Cleaning up warplot #{state.match_id}")
    {:stop, :normal, state}
  end

  # Private functions

  defp build_team_state(warplot) do
    %{
      guild_id: warplot.guild_id,
      warplot: warplot,
      members: [],
      kills: 0,
      deaths: 0
    }
  end

  defp initialize_resource_nodes do
    # 5 resource nodes in the contested middle zone
    Enum.reduce(1..5, %{}, fn id, acc ->
      Map.put(acc, id, %{id: id, owner: :neutral, position: {0.0, 0.0, 0.0}})
    end)
  end

  defp schedule_score_tick do
    Process.send_after(self(), :score_tick, @score_tick_interval_ms)
  end

  defp apply_generator_damage(state, :team1, amount) do
    # Damage team1's generator (team2 is attacking)
    new_health = max(0, state.team1_generator_health - amount)

    if new_health == 0 do
      # Generator destroyed - instant win for team2
      end_match(state, :generator_destroyed)
    else
      %{state | team1_generator_health: new_health}
    end
  end

  defp apply_generator_damage(state, :team2, amount) do
    # Damage team2's generator (team1 is attacking)
    new_health = max(0, state.team2_generator_health - amount)

    if new_health == 0 do
      # Generator destroyed - instant win for team1
      end_match(state, :generator_destroyed)
    else
      %{state | team2_generator_health: new_health}
    end
  end

  defp process_boss_kill(state, :team1) do
    # Team1's boss killed - team2 gets points
    %{
      state
      | team1_boss_alive: false,
        team2_score: state.team2_score + @boss_kill_points
    }
  end

  defp process_boss_kill(state, :team2) do
    # Team2's boss killed - team1 gets points
    %{
      state
      | team2_boss_alive: false,
        team1_score: state.team1_score + @boss_kill_points
    }
  end

  defp capture_node(state, node_id, team) do
    nodes =
      Map.update!(state.resource_nodes, node_id, fn node ->
        %{node | owner: team}
      end)

    %{state | resource_nodes: nodes}
  end

  defp process_kill(state, killer_guid, _victim_guid) do
    # Update kill/death counts
    team1_members = state.team1.members

    if killer_guid in team1_members do
      team1 = %{state.team1 | kills: state.team1.kills + 1}
      team2 = %{state.team2 | deaths: state.team2.deaths + 1}
      %{state | team1: team1, team2: team2}
    else
      team2 = %{state.team2 | kills: state.team2.kills + 1}
      team1 = %{state.team1 | deaths: state.team1.deaths + 1}
      %{state | team1: team1, team2: team2}
    end
  end

  defp process_score_tick(state) do
    team1_nodes = count_owned_nodes(state.resource_nodes, :team1)
    team2_nodes = count_owned_nodes(state.resource_nodes, :team2)

    %{
      state
      | team1_score: state.team1_score + team1_nodes * @resource_points_per_tick,
        team2_score: state.team2_score + team2_nodes * @resource_points_per_tick
    }
  end

  defp count_owned_nodes(nodes, team) do
    Enum.count(nodes, fn {_id, node} -> node.owner == team end)
  end

  defp check_victory(state) do
    cond do
      # Generator destroyed - already handled
      state.team1_generator_health == 0 ->
        end_match(state, :team2_generator_destroyed)

      state.team2_generator_health == 0 ->
        end_match(state, :team1_generator_destroyed)

      # Score limit reached
      state.team1_score >= @score_to_win ->
        end_match(state, :team1_score_limit)

      state.team2_score >= @score_to_win ->
        end_match(state, :team2_score_limit)

      true ->
        state
    end
  end

  defp end_match(state, reason) do
    winner =
      case reason do
        :team1_generator_destroyed ->
          :team1

        :team2_generator_destroyed ->
          :team2

        :team1_score_limit ->
          :team1

        :team2_score_limit ->
          :team2

        :generator_destroyed when state.team1_generator_health == 0 ->
          :team2

        :generator_destroyed ->
          :team1

        :time_expired ->
          cond do
            state.team1_score > state.team2_score -> :team1
            state.team2_score > state.team1_score -> :team2
            true -> :draw
          end

        _ ->
          :draw
      end

    Logger.info("Warplot #{state.match_id} ending - #{reason}")

    state = %{
      state
      | match_state: @match_state_ending,
        winner: winner
    }

    Process.send_after(self(), :ending_complete, @ending_time_ms)

    state
  end

  defp record_match_results(state) do
    spawn(fn ->
      # Record results for both guilds
      Warplots.record_battle(
        state.team1.guild_id,
        state.winner == :team1,
        state.team1_score
      )

      Warplots.record_battle(
        state.team2.guild_id,
        state.winner == :team2,
        state.team2_score
      )

      # Award war coins
      winner_coins = 500
      loser_coins = 100

      if state.winner == :team1 do
        Warplots.add_war_coins(state.team1.warplot.id, winner_coins)
        Warplots.add_war_coins(state.team2.warplot.id, loser_coins)
      else
        Warplots.add_war_coins(state.team2.warplot.id, winner_coins)
        Warplots.add_war_coins(state.team1.warplot.id, loser_coins)
      end
    end)
  end
end
