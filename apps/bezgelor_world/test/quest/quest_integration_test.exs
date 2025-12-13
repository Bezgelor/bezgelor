defmodule BezgelorWorld.Quest.IntegrationTest do
  @moduledoc """
  Integration tests for the quest system.

  Tests the complete flow from game events through session management,
  persistence, and packet generation.
  """
  use ExUnit.Case, async: true

  alias BezgelorWorld.Quest.{SessionQuestManager, QuestCache}

  # ============================================================================
  # Full Quest Lifecycle Tests
  # ============================================================================

  describe "quest lifecycle integration" do
    test "full quest accept -> progress -> complete flow" do
      # Start with empty session
      session_data = %{
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      character_id = 1
      quest_id = 100

      # Create a mock quest in session (simulating accept)
      quest = %{
        quest_id: quest_id,
        state: :accepted,
        objectives: [
          %{index: 0, current: 0, target: 3, type: 2, data: 456}
        ],
        dirty: false
      }

      session_data = put_in(session_data[:active_quests][quest_id], quest)

      # Progress through 3 kill events
      {session_data, packets_1} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert length(packets_1) == 1
      assert get_objective_progress(session_data, quest_id, 0) == 1

      {session_data, packets_2} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert length(packets_2) == 1
      assert get_objective_progress(session_data, quest_id, 0) == 2

      {session_data, packets_3} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert length(packets_3) == 1
      assert get_objective_progress(session_data, quest_id, 0) == 3

      # Quest should now be complete
      quest = session_data[:active_quests][quest_id]
      assert quest.state == :complete

      # Turn in should work
      case SessionQuestManager.turn_in_quest(session_data, character_id, quest_id) do
        {:ok, updated_session, {opcode, _packet}} ->
          assert opcode == :server_quest_remove
          refute Map.has_key?(updated_session[:active_quests], quest_id)
          assert MapSet.member?(updated_session[:completed_quest_ids], quest_id)

        {:error, reason} ->
          # DB might not be available in unit test context
          assert reason in [:not_found, :quest_not_found]
      end
    end

    test "quest does not over-increment past target" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            objectives: [
              %{index: 0, current: 2, target: 3, type: 2, data: 456}
            ],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      # Process multiple events that should cap at target
      {session_data, _} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert get_objective_progress(session_data, 100, 0) == 3

      # Another kill should not increment past target
      {session_data, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert get_objective_progress(session_data, 100, 0) == 3
      assert packets == []  # No packet since nothing changed
    end

    test "multiple quests with same objective type track independently" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            objectives: [%{index: 0, current: 0, target: 2, type: 2, data: 456}],
            dirty: false
          },
          200 => %{
            quest_id: 200,
            state: :accepted,
            objectives: [%{index: 0, current: 0, target: 5, type: 2, data: 456}],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      {session_data, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      # Both quests should have incremented
      assert get_objective_progress(session_data, 100, 0) == 1
      assert get_objective_progress(session_data, 200, 0) == 1
      assert length(packets) == 2

      # Quest 100 has target 2, so one more kill should complete it
      {session_data, _} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert session_data[:active_quests][100].state == :complete
      assert session_data[:active_quests][200].state == :accepted
    end
  end

  # ============================================================================
  # Event Type Coverage Tests
  # ============================================================================

  describe "event type coverage" do
    test "interact event increments interact_object objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 12, data: 789}  # interact_object
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :interact,
        %{object_id: 789}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "enter_location event increments location objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 5, data: 1234}  # enter_location
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :enter_location,
        %{location_id: 1234}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "talk_npc event increments talk_to_npc objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 4, data: 555}  # talk_to_npc
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :talk_npc,
        %{creature_id: 555}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "use_item event increments use_item objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 8, data: 2001}  # use_item
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :use_item,
        %{item_id: 2001}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "use_ability event increments use_ability objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 17, data: 3000}  # use_ability
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :use_ability,
        %{spell_id: 3000}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "gather event increments gather_resource objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 33, data: 4000}  # gather_resource
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :gather,
        %{node_id: 4000}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "complete_event event increments complete_event objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 31, data: 5000}  # complete_event
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :complete_event,
        %{event_id: 5000}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "condition_met event increments achieve_condition objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 32, data: 6000}  # achieve_condition
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :condition_met,
        %{condition_id: 6000}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  # ============================================================================
  # Multi-Objective Quest Tests
  # ============================================================================

  describe "multi-objective quests" do
    test "quest with multiple objectives tracks each independently" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            objectives: [
              %{index: 0, current: 0, target: 2, type: 2, data: 100},   # Kill creature 100
              %{index: 1, current: 0, target: 3, type: 3, data: 200},   # Collect item 200
              %{index: 2, current: 0, target: 1, type: 12, data: 300}   # Interact object 300
            ],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      # Kill creature - only objective 0 increments
      {session_data, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 100}
      )

      assert get_objective_progress(session_data, 100, 0) == 1
      assert get_objective_progress(session_data, 100, 1) == 0
      assert get_objective_progress(session_data, 100, 2) == 0
      assert length(packets) == 1

      # Loot item - only objective 1 increments
      {session_data, packets} = SessionQuestManager.process_game_event(
        session_data,
        :loot,
        %{item_id: 200}
      )

      assert get_objective_progress(session_data, 100, 0) == 1
      assert get_objective_progress(session_data, 100, 1) == 1
      assert get_objective_progress(session_data, 100, 2) == 0
      assert length(packets) == 1

      # Quest not complete yet
      assert session_data[:active_quests][100].state == :accepted
    end

    test "quest completes when all objectives are done" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            objectives: [
              %{index: 0, current: 1, target: 2, type: 2, data: 100},  # 1/2 kills
              %{index: 1, current: 2, target: 2, type: 3, data: 200}   # 2/2 items (complete)
            ],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      # Final kill to complete objective 0
      {session_data, _} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 100}
      )

      # Quest should now be complete
      assert session_data[:active_quests][100].state == :complete
    end
  end

  # ============================================================================
  # Dirty Flag and Persistence Tests
  # ============================================================================

  describe "dirty flag tracking" do
    test "dirty flag is set when quest is updated" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 2, data: 456}
      )

      refute session_data[:active_quests][100].dirty
      refute session_data[:quest_dirty]

      {updated, _} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert updated[:active_quests][100].dirty
      assert updated[:quest_dirty]
    end

    test "dirty flag is not set when no matching event" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 2, data: 456}
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 999}  # Wrong creature
      )

      refute updated[:active_quests][100].dirty
      assert packets == []
    end
  end

  describe "QuestCache utility functions" do
    test "get_dirty_quests returns only dirty quests" do
      active_quests = %{
        100 => %{quest_id: 100, dirty: true},
        200 => %{quest_id: 200, dirty: false},
        300 => %{quest_id: 300, dirty: true}
      }

      dirty = QuestCache.get_dirty_quests(active_quests)
      dirty_ids = Enum.map(dirty, & &1.quest_id) |> Enum.sort()

      assert dirty_ids == [100, 300]
    end

    test "clear_dirty_flags clears all dirty flags" do
      active_quests = %{
        100 => %{quest_id: 100, dirty: true},
        200 => %{quest_id: 200, dirty: true}
      }

      cleared = QuestCache.clear_dirty_flags(active_quests)

      refute cleared[100].dirty
      refute cleared[200].dirty
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "empty session handles events gracefully" do
      session_data = %{
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert updated == session_data
      assert packets == []
    end

    test "completed quests ignore events" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :complete,  # Already complete
            objectives: [
              %{index: 0, current: 3, target: 3, type: 2, data: 456}
            ],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      # No change
      assert updated[:active_quests][100].objectives == session_data[:active_quests][100].objectives
      assert packets == []
    end

    test "turn_in fails for non-complete quest" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            objectives: [%{index: 0, current: 1, target: 3, type: 2, data: 456}],
            dirty: false
          }
        },
        completed_quest_ids: MapSet.new()
      }

      result = SessionQuestManager.turn_in_quest(session_data, 1, 100)
      assert {:error, :quest_not_complete} = result
    end

    test "abandon non-existent quest returns error" do
      session_data = %{
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      result = SessionQuestManager.abandon_quest(session_data, 1, 99999)
      assert {:error, :quest_not_found} = result
    end
  end

  # ============================================================================
  # Additional Objective Type Tests (new types)
  # ============================================================================

  describe "item objective types" do
    test "deliver_item event increments deliver_item objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 6, data: 1001}  # deliver_item
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :deliver_item,
        %{item_id: 1001, npc_id: 500}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "equip_item event increments equip_item objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 7, data: 2002}  # equip_item
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :equip_item,
        %{item_id: 2002}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "craft event increments craft_item objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 13, data: 3003}  # craft_item
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :craft,
        %{item_id: 3003}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "interaction objective types" do
    test "datacube event increments activate_datacube objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 20, data: 4004}  # activate_datacube
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :datacube,
        %{datacube_id: 4004}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "scan event increments scan_creature objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 21, data: 5005}  # scan_creature
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :scan,
        %{creature_id: 5005}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "location objective types" do
    test "explore event increments explore objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 25, data: 6006}  # explore
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :enter_location,
        %{location_id: 6006}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "discover_poi event increments discover_poi objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 15, data: 7007}  # discover_poi
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :discover_poi,
        %{poi_id: 7007}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "escort/defense objective types" do
    test "escort_complete event increments escort_npc objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 14, data: 8008}  # escort_npc
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :escort_complete,
        %{escort_id: 8008}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "defend_complete event increments defend_location objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 18, data: 9009}  # defend_location
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :defend_complete,
        %{location_id: 9009}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "event/sequence objective types" do
    test "dungeon_complete event increments complete_dungeon objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 9, data: 1010}  # complete_dungeon
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :dungeon_complete,
        %{dungeon_id: 1010}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "sequence_step event increments objective_sequence objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 11, data: 1111}  # objective_sequence
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :sequence_step,
        %{sequence_id: 1111}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "timed_complete event increments timed_event objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 16, data: 1212}  # timed_event
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :timed_complete,
        %{timer_id: 1212}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "path objective types" do
    test "path_complete event increments path_mission objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 19, data: 1313}  # path_mission
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :path_complete,
        %{mission_id: 1313}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "pvp/competitive objective types" do
    test "pvp_win event increments win_pvp objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 28, data: 1414}  # win_pvp
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :pvp_win,
        %{battleground_id: 1414}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "pvp_win with zero data matches any battleground" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 28, data: 0}  # win_pvp any
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :pvp_win,
        %{battleground_id: 9999}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "capture event increments capture_point objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 3, type: 29, data: 1515}  # capture_point
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :capture,
        %{point_id: 1515}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "challenge_complete event increments challenge objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 35, data: 1616}  # challenge
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :challenge_complete,
        %{challenge_id: 1616}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "specialized objective types" do
    test "reputation_gain event increments reputation objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 36, data: 1717}  # reputation
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :reputation_gain,
        %{faction_id: 1717, level: 3}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "level_up event increments level_requirement objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 37, data: 20}  # level_requirement
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :level_up,
        %{level: 25}  # Greater than required 20
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "level_up event does not increment if level too low" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 37, data: 30}  # requires level 30
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :level_up,
        %{level: 25}  # Less than required 30
      )

      assert get_objective_progress(updated, 100, 0) == 0
      assert packets == []
    end

    test "achievement event increments achievement objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 44, data: 1818}  # achievement
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :achievement,
        %{achievement_id: 1818}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "title event increments title objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 42, data: 1919}  # title
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :title,
        %{title_id: 1919}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "housing event increments housing objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 39, data: 2020}  # housing
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :housing,
        %{housing_id: 2020}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "mount event increments mount objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 40, data: 2121}  # mount
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :mount,
        %{mount_id: 2121}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "costume event increments costume objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 41, data: 2222}  # costume
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :costume,
        %{costume_id: 2222}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "currency event increments currency objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 46, data: 2323}  # currency
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :currency,
        %{currency_id: 2323, amount: 100}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "social event increments social objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 47, data: 2424}  # social
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :social,
        %{social_type: 2424}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "guild event increments guild objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 48, data: 2525}  # guild
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :guild,
        %{guild_action: 2525}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  describe "special/scripted objective types" do
    test "special event increments special objectives" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 27, data: 2626}  # special
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :special,
        %{special_id: 2626}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  # ============================================================================
  # Generic Objective Type Tests
  # ============================================================================

  describe "generic objective type (38)" do
    test "generic objectives match kill events" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 38, data: 456}  # generic
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 456}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "generic objectives match loot events" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 38, data: 789}  # generic
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :loot,
        %{item_id: 789}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end

    test "generic objectives match interact events" do
      session_data = build_session_with_quest(
        quest_id: 100,
        objective: %{index: 0, current: 0, target: 1, type: 38, data: 1000}  # generic
      )

      {updated, packets} = SessionQuestManager.process_game_event(
        session_data,
        :interact,
        %{object_id: 1000}
      )

      assert get_objective_progress(updated, 100, 0) == 1
      assert length(packets) == 1
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp build_session_with_quest(opts) do
    quest_id = Keyword.fetch!(opts, :quest_id)
    objective = Keyword.fetch!(opts, :objective)

    %{
      active_quests: %{
        quest_id => %{
          quest_id: quest_id,
          state: :accepted,
          objectives: [objective],
          dirty: false
        }
      },
      completed_quest_ids: MapSet.new()
    }
  end

  defp get_objective_progress(session_data, quest_id, index) do
    quest = session_data[:active_quests][quest_id]
    obj = Enum.find(quest.objectives, &(&1.index == index))
    obj.current
  end
end
