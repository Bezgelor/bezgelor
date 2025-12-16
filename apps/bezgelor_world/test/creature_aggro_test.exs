defmodule BezgelorWorld.CreatureAggroTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager

  setup do
    # Start CreatureManager if not running
    case GenServer.whereis(CreatureManager) do
      nil -> start_supervised!(CreatureManager)
      _pid -> :ok
    end

    # Clear any existing creatures
    CreatureManager.clear_all_creatures()
    :ok
  end

  describe "check_aggro_for_creature/2" do
    test "creature enters combat when player within aggro range" do
      # Spawn an aggressive creature (template 2 = Forest Wolf with aggro_range 15.0)
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Verify starts idle
      {:ok, initial_state} = CreatureManager.get_creature_state(creature_guid)
      assert initial_state.ai.state == :idle

      # Simulate player entity nearby (within 15.0 aggro range)
      player = %{
        guid: 0x1000000000000001,
        position: {10.0, 0.0, 0.0}  # 10 units away
      }

      # Trigger aggro check with player context
      CreatureManager.check_aggro_for_creature(creature_guid, [player])

      # Allow async processing
      Process.sleep(50)

      # Verify creature entered combat
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.state == :combat
      assert state.ai.target_guid == player.guid
    end

    test "creature stays idle when player outside aggro range" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Simulate player entity far away (outside 15.0 aggro range)
      player = %{
        guid: 0x1000000000000001,
        position: {50.0, 0.0, 0.0}  # 50 units away
      }

      CreatureManager.check_aggro_for_creature(creature_guid, [player])
      Process.sleep(50)

      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.state == :idle
    end

    test "creature already in combat ignores new aggro checks" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Put creature in combat with first player
      first_player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, first_player_guid)
      Process.sleep(50)

      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :combat
      assert state1.ai.target_guid == first_player_guid

      # Try to aggro with second player (closer)
      second_player = %{
        guid: 0x1000000000000002,
        position: {5.0, 0.0, 0.0}
      }

      CreatureManager.check_aggro_for_creature(creature_guid, [second_player])
      Process.sleep(50)

      # Should still have original target
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.target_guid == first_player_guid
    end
  end

  describe "get_creature_state/1" do
    test "returns creature state for valid guid" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {5.0, 10.0, 15.0})

      {:ok, state} = CreatureManager.get_creature_state(creature_guid)

      assert state.entity.guid == creature_guid
      assert state.spawn_position == {5.0, 10.0, 15.0}
      assert state.ai.state == :idle
    end

    test "returns error for invalid guid" do
      result = CreatureManager.get_creature_state(0xDEADBEEF)
      assert result == :error
    end
  end
end
