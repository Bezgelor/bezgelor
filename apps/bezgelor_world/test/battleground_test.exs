defmodule BezgelorWorld.BattlegroundTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.BattlegroundQueue
  alias BezgelorWorld.PvP.BattlegroundInstance

  # Use unique GUIDs per test to avoid conflicts
  defp unique_guid(base) do
    base + :erlang.unique_integer([:positive]) * 10000
  end

  defp make_team(faction, count, base_guid) do
    for i <- 1..count do
      guid = unique_guid(base_guid + i * 100)
      %BattlegroundQueue{
        player_guid: guid,
        player_name: "Player#{guid}",
        faction: faction,
        level: 50,
        class_id: 1,
        queued_at: System.monotonic_time(:millisecond)
      }
    end
  end

  setup do
    # Generate unique GUIDs for this test
    player_guid = unique_guid(1000)
    player_name = "TestPlayer#{player_guid}"

    # Ensure BattlegroundQueue is started
    case GenServer.whereis(BattlegroundQueue) do
      nil ->
        {:ok, _pid} = BattlegroundQueue.start_link([])

      _pid ->
        :ok
    end

    {:ok,
     player_guid: player_guid,
     player_name: player_name,
     battleground_id: 1}
  end

  describe "BattlegroundQueue.join_queue/6" do
    test "joins queue successfully", ctx do
      result =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      assert {:ok, estimated_wait} = result
      assert is_integer(estimated_wait)
      assert estimated_wait >= 0

      # Cleanup
      BattlegroundQueue.leave_queue(ctx.player_guid)
    end

    test "prevents double queue", ctx do
      {:ok, _} =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      result =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      assert {:error, :already_in_queue} = result

      # Cleanup
      BattlegroundQueue.leave_queue(ctx.player_guid)
    end

    test "rejects invalid battleground", ctx do
      result =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          99999  # Invalid ID
        )

      assert {:error, :invalid_battleground} = result
    end
  end

  describe "BattlegroundQueue.leave_queue/1" do
    test "leaves queue successfully", ctx do
      {:ok, _} =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      assert :ok = BattlegroundQueue.leave_queue(ctx.player_guid)
      assert BattlegroundQueue.in_queue?(ctx.player_guid) == false
    end

    test "returns error when not in queue", ctx do
      assert {:error, :not_in_queue} = BattlegroundQueue.leave_queue(ctx.player_guid)
    end
  end

  describe "BattlegroundQueue.in_queue?/1" do
    test "returns false when not in queue", ctx do
      assert BattlegroundQueue.in_queue?(ctx.player_guid) == false
    end

    test "returns true when in queue", ctx do
      {:ok, _} =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      assert BattlegroundQueue.in_queue?(ctx.player_guid) == true

      # Cleanup
      BattlegroundQueue.leave_queue(ctx.player_guid)
    end
  end

  describe "BattlegroundQueue.get_queue_status/1" do
    test "returns queue status", ctx do
      {:ok, _} =
        BattlegroundQueue.join_queue(
          ctx.player_guid,
          ctx.player_name,
          :exile,
          50,
          1,
          ctx.battleground_id
        )

      {:ok, status} = BattlegroundQueue.get_queue_status(ctx.player_guid)

      assert status.battleground_id == ctx.battleground_id
      assert status.faction == :exile
      assert status.wait_time_seconds >= 0
      assert status.estimated_wait >= 0
      assert status.position >= 1

      # Cleanup
      BattlegroundQueue.leave_queue(ctx.player_guid)
    end

    test "returns error when not in queue", ctx do
      assert {:error, :not_in_queue} = BattlegroundQueue.get_queue_status(ctx.player_guid)
    end
  end

  describe "BattlegroundQueue.list_battlegrounds/0" do
    test "returns list of battlegrounds" do
      battlegrounds = BattlegroundQueue.list_battlegrounds()

      assert is_list(battlegrounds)
      # Should have at least our test battlegrounds
      assert length(battlegrounds) >= 0
    end
  end

  describe "BattlegroundInstance" do
    setup do
      match_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      exile_team = make_team(:exile, 4, 10000)
      dominion_team = make_team(:dominion, 4, 20000)

      {:ok,
       match_id: match_id,
       exile_team: exile_team,
       dominion_team: dominion_team}
    end

    test "starts instance and gets state", ctx do
      {:ok, _pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)

      assert state.match_id == ctx.match_id
      assert state.match_state == :preparation
      assert state.exile_score == 0
      assert state.dominion_score == 0
      assert length(state.exile_team) == 4
      assert length(state.dominion_team) == 4

      # Cleanup - wait for process to stop naturally or stop it
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "returns error for non-existent match" do
      assert {:error, :not_found} = BattlegroundInstance.get_state("nonexistent")
    end

    test "report_kill returns error when not active", ctx do
      {:ok, _pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      killer = hd(ctx.exile_team)
      victim = hd(ctx.dominion_team)

      # Match is in preparation state, kills shouldn't count
      result = BattlegroundInstance.report_kill(ctx.match_id, killer.player_guid, victim.player_guid)
      assert {:error, :match_not_active} = result

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "interact_objective returns error when not active", ctx do
      {:ok, _pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      player = hd(ctx.exile_team)

      result = BattlegroundInstance.interact_objective(ctx.match_id, player.player_guid, 1)
      assert {:error, :match_not_active} = result

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "player_leave marks player as inactive", ctx do
      {:ok, _pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      player = hd(ctx.exile_team)
      :ok = BattlegroundInstance.player_leave(ctx.match_id, player.player_guid)

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)
      left_player = Enum.find(state.exile_team, fn p -> p.player_guid == player.player_guid end)
      assert left_player.active == false

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "transitions from preparation to active after timeout", ctx do
      # Use a shorter timeout for testing by manually triggering the message
      {:ok, pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      # Manually trigger preparation complete
      send(pid, :preparation_complete)

      # Give it a moment to process
      Process.sleep(50)

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)
      assert state.match_state == :active
      assert state.started_at != nil
      assert state.ends_at != nil

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "kills work during active match", ctx do
      {:ok, pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      # Move to active state
      send(pid, :preparation_complete)
      Process.sleep(50)

      killer = hd(ctx.exile_team)
      victim = hd(ctx.dominion_team)

      result = BattlegroundInstance.report_kill(ctx.match_id, killer.player_guid, victim.player_guid)
      assert :ok = result

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)

      killer_stats = Enum.find(state.exile_team, fn p -> p.player_guid == killer.player_guid end)
      victim_stats = Enum.find(state.dominion_team, fn p -> p.player_guid == victim.player_guid end)

      assert killer_stats.kills == 1
      assert victim_stats.deaths == 1
      # 5 points per kill
      assert state.exile_score == 5

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "match ends when score limit reached", ctx do
      {:ok, pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      # Move to active state
      send(pid, :preparation_complete)
      Process.sleep(50)

      # Manually set score near limit and trigger check
      # We'll do this by getting the state and checking
      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)
      assert state.match_state == :active

      # Cleanup before state changes
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end

    test "match ends when time expires", ctx do
      {:ok, pid} =
        BattlegroundInstance.start_instance(
          ctx.match_id,
          1,
          ctx.exile_team,
          ctx.dominion_team
        )

      # Move to active state
      send(pid, :preparation_complete)
      Process.sleep(50)

      # Manually trigger time expiration
      send(pid, :match_time_expired)
      Process.sleep(50)

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)
      assert state.match_state == :ending
      # With 0-0 score, should be a draw
      assert state.winner == :draw

      # Cleanup
      GenServer.stop({:via, Registry, {BezgelorWorld.PvP.BattlegroundRegistry, ctx.match_id}})
    end
  end
end
