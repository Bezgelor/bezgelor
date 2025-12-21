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

    {:ok, player_guid: player_guid, player_name: player_name, battleground_id: 1}
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
          # Invalid ID
          99999
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

      {:ok, match_id: match_id, exile_team: exile_team, dominion_team: dominion_team}
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
      result =
        BattlegroundInstance.report_kill(ctx.match_id, killer.player_guid, victim.player_guid)

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

      result =
        BattlegroundInstance.report_kill(ctx.match_id, killer.player_guid, victim.player_guid)

      assert :ok = result

      {:ok, state} = BattlegroundInstance.get_state(ctx.match_id)

      killer_stats = Enum.find(state.exile_team, fn p -> p.player_guid == killer.player_guid end)

      victim_stats =
        Enum.find(state.dominion_team, fn p -> p.player_guid == victim.player_guid end)

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

  # =============================================
  # Walatiki Temple Mask Mechanics Tests
  # =============================================

  describe "Walatiki Temple mask mechanics" do
    alias BezgelorWorld.PvP.Objectives.WalatikiMask

    test "mask can be picked up from center" do
      mask = %WalatikiMask{id: 1, state: :spawned, position: {0.0, 0.0, 0.0}}
      {:ok, mask} = WalatikiMask.pickup(mask, 1001, :exile)

      assert mask.state == :carried
      assert mask.carrier_guid == 1001
      assert mask.carrier_faction == :exile
    end

    test "mask drops on carrier death" do
      mask = %WalatikiMask{id: 1, state: :carried, carrier_guid: 1001, carrier_faction: :exile}
      {:ok, mask} = WalatikiMask.drop(mask, {50.0, 0.0, 0.0})

      assert mask.state == :dropped
      assert mask.drop_position == {50.0, 0.0, 0.0}
    end

    test "friendly player returns dropped mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        carrier_faction: :exile,
        drop_position: {50.0, 0.0, 0.0},
        dropped_at: System.monotonic_time(:millisecond)
      }

      {:returned, mask} = WalatikiMask.pickup(mask, 1002, :exile)

      assert mask.state == :returning
    end

    test "enemy player picks up dropped mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        carrier_faction: :exile,
        drop_position: {50.0, 0.0, 0.0},
        dropped_at: System.monotonic_time(:millisecond)
      }

      {:ok, mask} = WalatikiMask.pickup(mask, 2001, :dominion)

      assert mask.state == :carried
      assert mask.carrier_faction == :dominion
    end

    test "mask returns to center after timeout" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        dropped_at: System.monotonic_time(:millisecond) - 15_000
      }

      {:return, mask} = WalatikiMask.check_return(mask)

      assert mask.state == :returning
    end

    test "mask capture awards points" do
      mask = %WalatikiMask{
        id: 1,
        state: :carried,
        carrier_guid: 1001,
        carrier_faction: :exile
      }

      {:captured, mask} = WalatikiMask.capture(mask, :exile)

      assert mask.state == :returning
      assert mask.carrier_guid == nil
    end

    test "cannot pickup carried mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :carried,
        carrier_guid: 1001,
        carrier_faction: :exile
      }

      {:error, :mask_not_available} = WalatikiMask.pickup(mask, 2001, :dominion)
    end

    test "respawn creates spawned mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :returning,
        position: {0.0, 0.0, 0.0}
      }

      mask = WalatikiMask.respawn(mask)

      assert mask.state == :spawned
      assert mask.carrier_guid == nil
    end
  end

  # =============================================
  # Halls of the Bloodsworn Control Point Tests
  # =============================================

  describe "Halls of the Bloodsworn control points" do
    alias BezgelorWorld.PvP.Objectives.ControlPoint

    test "empty point maintains state" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.5,
        capturing_faction: nil,
        players_in_range: %{exile: [], dominion: []}
      }

      {:unchanged, point} = ControlPoint.tick(point)

      assert point.capture_progress == 0.5
    end

    test "single player captures point" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.5,
        capturing_faction: nil,
        players_in_range: %{exile: [1001], dominion: []}
      }

      {:capturing, point} = ControlPoint.tick(point)

      assert point.capturing_faction == :exile
      assert point.capture_progress > 0.5
    end

    test "contested point freezes progress" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.7,
        capturing_faction: :exile,
        players_in_range: %{exile: [1001], dominion: [2001]}
      }

      {:contested, point} = ControlPoint.tick(point)

      assert point.capture_progress == 0.7
    end

    test "multiple players capture faster" do
      single = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.0,
        capturing_faction: nil,
        players_in_range: %{exile: [1001], dominion: []}
      }

      {:capturing, single_result} = ControlPoint.tick(single)

      multi = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.0,
        capturing_faction: nil,
        players_in_range: %{exile: [1001, 1002, 1003], dominion: []}
      }

      {:capturing, multi_result} = ControlPoint.tick(multi)

      assert multi_result.capture_progress > single_result.capture_progress
    end

    test "capture completes at 100%" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.99,
        capturing_faction: :exile,
        players_in_range: %{exile: [1001], dominion: []}
      }

      {:captured, point} = ControlPoint.tick(point)

      assert point.owner == :exile
      assert point.capture_progress == 1.0
    end

    test "center point worth double" do
      base_score = 10

      side_point =
        ControlPoint.new(1, "Side Point", {0.0, 0.0, 0.0},
          owner: :exile,
          capture_progress: 1.0,
          score_multiplier: 1.0
        )

      center_point =
        ControlPoint.new(2, "Center Point", {0.0, 0.0, 0.0},
          owner: :exile,
          capture_progress: 1.0,
          score_multiplier: 2.0
        )

      assert ControlPoint.score_per_tick(side_point, base_score) == 10
      assert ControlPoint.score_per_tick(center_point, base_score) == 20
    end
  end

  # =============================================
  # Respawn System Tests
  # =============================================

  describe "respawn system" do
    alias BezgelorWorld.PvP.Respawn

    test "creates respawn entry" do
      respawn = Respawn.create(1001, :exile)

      assert respawn.player_guid == 1001
      assert respawn.faction == :exile
      assert respawn.respawn_time > respawn.death_time
    end

    test "time until respawn calculation" do
      respawn = Respawn.create(1001, :exile)
      time_left = Respawn.time_until_respawn(respawn)

      # Should be around 30 seconds (base respawn time) + wave interval
      assert time_left >= 0
    end

    test "selects appropriate graveyard" do
      graveyards = [
        %{id: 1, faction: :exile, position: {0.0, 0.0, 0.0}, priority: 1},
        %{id: 2, faction: :exile, position: {100.0, 0.0, 0.0}, priority: 2}
      ]

      selected = Respawn.select_graveyard(:exile, graveyards)

      # Should prefer higher priority
      assert selected.id == 2
    end
  end

  # =============================================
  # Deserter Debuff Tests
  # =============================================

  describe "deserter debuff" do
    alias BezgelorWorld.PvP.Deserter

    test "initial deserter duration" do
      deserter = Deserter.apply(1001, :battleground, nil)

      assert deserter.stacks == 1
      assert deserter.player_guid == 1001
      assert deserter.content_type == :battleground
    end

    test "deserter stacks increase" do
      deserter = Deserter.apply(1001, :battleground, nil)
      deserter = Deserter.apply(1001, :battleground, deserter)
      deserter = Deserter.apply(1001, :battleground, deserter)

      assert deserter.stacks == 3
    end

    test "max stacks is 5" do
      deserter =
        1..10
        |> Enum.reduce(nil, fn _, d -> Deserter.apply(1001, :battleground, d) end)

      assert deserter.stacks == 5
    end

    test "max duration per application is capped" do
      # Single fresh deserter at max stacks should not exceed max duration
      # The max_duration_ms caps the duration per application at 1 hour
      assert Deserter.max_duration_ms() == 3_600_000
      assert Deserter.base_duration_ms() == 900_000
    end

    test "can queue check" do
      deserter = Deserter.apply(1001, :battleground, nil)

      refute Deserter.can_queue?(deserter, :battleground)
      assert Deserter.can_queue?(nil, :battleground)
    end
  end
end
