defmodule BezgelorWorld.ArenaTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.Rating

  # =============================================
  # ELO Rating Calculations Tests
  # =============================================

  describe "ELO rating calculations" do
    test "higher rated player gains less for winning" do
      {high_gain, _} = Rating.calculate_elo_change(2000, 1500)
      {low_gain, _} = Rating.calculate_elo_change(1500, 2000)

      assert low_gain > high_gain
    end

    test "minimum rating change is 1" do
      {winner_gain, loser_loss} = Rating.calculate_elo_change(2500, 1000)

      assert winner_gain >= 1
      assert loser_loss >= 1
    end

    test "expected score calculation" do
      # Equal ratings = 50% expected
      assert_in_delta Rating.expected_score(1500, 1500), 0.5, 0.01

      # 400 point advantage = ~90% expected
      assert_in_delta Rating.expected_score(1900, 1500), 0.91, 0.02
    end

    test "k-factor decreases with games played" do
      assert Rating.k_factor(5) > Rating.k_factor(30)
      assert Rating.k_factor(30) > Rating.k_factor(100)
    end

    test "k-factor values" do
      assert Rating.k_factor(5) == 40
      assert Rating.k_factor(25) == 24
      assert Rating.k_factor(100) == 16
    end

    test "team rating is average of members" do
      assert Rating.team_rating([1500, 1600, 1700]) == 1600
      assert Rating.team_rating([1500]) == 1500
      assert Rating.team_rating([]) == 1500
    end

    test "rating is clamped within bounds" do
      assert Rating.clamp(-100) == 0
      assert Rating.clamp(10000) == 5000
      assert Rating.clamp(1500) == 1500
    end

    test "apply floor protection" do
      assert Rating.apply_floor(1800, 1500) == 1800
      assert Rating.apply_floor(1200, 1500) == 1500
    end

    test "apply ceiling" do
      assert Rating.apply_ceiling(4000) == 4000
      assert Rating.apply_ceiling(6000) == 5000
    end

    test "matchmaking quality based on rating difference" do
      assert Rating.matchmaking_quality(1500, 1500) == 1.0
      assert Rating.matchmaking_quality(1500, 1575) == 0.9
      assert Rating.matchmaking_quality(1500, 1650) == 0.7
      assert Rating.matchmaking_quality(1500, 1750) == 0.5
      assert Rating.matchmaking_quality(1500, 1850) == 0.3
      assert Rating.matchmaking_quality(1500, 2000) == 0.1
    end

    test "starting rating is 1500" do
      assert Rating.starting_rating() == 1500
    end

    test "min rating is 0" do
      assert Rating.min_rating() == 0
    end

    test "max rating is 5000" do
      assert Rating.max_rating() == 5000
    end
  end

  # =============================================
  # Arena Instance Tests
  # =============================================

  describe "ArenaInstance" do
    alias BezgelorWorld.PvP.ArenaInstance

    setup do
      # Ensure ArenaRegistry is started
      unless Process.whereis(BezgelorWorld.PvP.ArenaRegistry) do
        {:ok, _} = Registry.start_link(keys: :unique, name: BezgelorWorld.PvP.ArenaRegistry)
      end

      # Ensure ArenaSupervisor is started
      unless Process.whereis(BezgelorWorld.PvP.ArenaSupervisor) do
        {:ok, _pid} = BezgelorWorld.PvP.ArenaSupervisor.start_link([])
      end

      match_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      team1 = %{
        team_id: 1,
        team_name: "Team1",
        members: [1001, 1002],
        rating: 1500
      }

      team2 = %{
        team_id: 2,
        team_name: "Team2",
        members: [2001, 2002],
        rating: 1500
      }

      {:ok, match_id: match_id, team1: team1, team2: team2}
    end

    test "starts instance and gets state", ctx do
      {:ok, _pid} =
        ArenaInstance.start_instance(ctx.match_id, "2v2", ctx.team1, ctx.team2)

      state = ArenaInstance.get_state(ctx.match_id)

      assert state.match_id == ctx.match_id
      assert state.bracket == "2v2"
      assert state.match_state == :preparation
      assert state.team1_alive == 2
      assert state.team2_alive == 2
      assert state.dampening_percent == 0

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id}})
    end

    test "returns error for non-existent match" do
      assert {:error, :not_found} = ArenaInstance.get_state("nonexistent")
    end

    test "report_death returns error when not active", ctx do
      {:ok, _pid} =
        ArenaInstance.start_instance(ctx.match_id, "2v2", ctx.team1, ctx.team2)

      # Match is in preparation state, deaths shouldn't process
      result = ArenaInstance.report_death(ctx.match_id, 2001)
      assert {:error, :match_not_active} = result

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id}})
    end

    test "transitions from preparation to active after timeout", ctx do
      {:ok, pid} =
        ArenaInstance.start_instance(ctx.match_id, "2v2", ctx.team1, ctx.team2)

      # Manually trigger preparation complete
      send(pid, :preparation_complete)
      Process.sleep(50)

      state = ArenaInstance.get_state(ctx.match_id)
      assert state.match_state == :active
      assert state.started_at != nil

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id}})
    end

    test "deaths work during active match", ctx do
      {:ok, pid} =
        ArenaInstance.start_instance(ctx.match_id, "2v2", ctx.team1, ctx.team2)

      # Move to active state
      send(pid, :preparation_complete)
      Process.sleep(50)

      result = ArenaInstance.report_death(ctx.match_id, 2001)
      assert :ok = result

      state = ArenaInstance.get_state(ctx.match_id)
      assert state.team2_alive == 1

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id}})
    end

    test "match ends when all players on one team die", ctx do
      {:ok, pid} =
        ArenaInstance.start_instance(ctx.match_id, "2v2", ctx.team1, ctx.team2)

      # Move to active state
      send(pid, :preparation_complete)
      Process.sleep(50)

      # Kill team 2
      ArenaInstance.report_death(ctx.match_id, 2001)
      ArenaInstance.report_death(ctx.match_id, 2002)

      state = ArenaInstance.get_state(ctx.match_id)
      assert state.match_state == :ending
      assert state.winner == :team1

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id}})
    end

    test "bracket_size for different brackets", ctx do
      # 2v2
      {:ok, pid2v2} =
        ArenaInstance.start_instance(ctx.match_id <> "-2v2", "2v2", ctx.team1, ctx.team2)

      state2v2 = ArenaInstance.get_state(ctx.match_id <> "-2v2")
      assert state2v2.team1_alive == 2

      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id <> "-2v2"}})

      # 3v3
      team1_3v3 = %{ctx.team1 | members: [1001, 1002, 1003]}
      team2_3v3 = %{ctx.team2 | members: [2001, 2002, 2003]}

      {:ok, pid3v3} =
        ArenaInstance.start_instance(ctx.match_id <> "-3v3", "3v3", team1_3v3, team2_3v3)

      state3v3 = ArenaInstance.get_state(ctx.match_id <> "-3v3")
      assert state3v3.team1_alive == 3

      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, ctx.match_id <> "-3v3"}})
    end
  end

  # =============================================
  # Arena Supervisor Tests
  # =============================================

  describe "ArenaSupervisor" do
    alias BezgelorWorld.PvP.ArenaSupervisor

    setup do
      # Ensure ArenaRegistry is started
      unless Process.whereis(BezgelorWorld.PvP.ArenaRegistry) do
        {:ok, _} = Registry.start_link(keys: :unique, name: BezgelorWorld.PvP.ArenaRegistry)
      end

      # Ensure ArenaSupervisor is started
      unless Process.whereis(ArenaSupervisor) do
        {:ok, _pid} = ArenaSupervisor.start_link([])
      end

      :ok
    end

    test "active_count returns integer" do
      count = ArenaSupervisor.active_count()
      assert is_integer(count)
      assert count >= 0
    end

    test "list_matches returns list" do
      matches = ArenaSupervisor.list_matches()
      assert is_list(matches)
    end
  end
end
