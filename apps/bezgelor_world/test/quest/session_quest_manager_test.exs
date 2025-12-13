defmodule BezgelorWorld.Quest.SessionQuestManagerTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Quest.SessionQuestManager

  describe "process_game_event/3" do
    test "updates kill objective when creature matches" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 0, target: 5}  # Kill creature 12345
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 12345}
      )

      # Verify objective incremented
      quest = updated_session.active_quests[100]
      assert quest.dirty == true
      assert Enum.at(quest.objectives, 0).current == 1

      # Verify packet generated
      assert length(packets) == 1
    end

    test "does not update when creature doesn't match" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 0, target: 5}
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 99999}  # Different creature
      )

      # Verify no update
      quest = updated_session.active_quests[100]
      assert quest.dirty == false
      assert Enum.at(quest.objectives, 0).current == 0
      assert packets == []
    end

    test "updates loot objective when item matches" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 3, data: 5001, current: 2, target: 10}  # Collect item 5001
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :loot,
        %{item_id: 5001}
      )

      quest = updated_session.active_quests[100]
      assert quest.dirty == true
      assert Enum.at(quest.objectives, 0).current == 3
      assert length(packets) == 1
    end

    test "marks quest complete when all objectives met" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 4, target: 5}  # 4/5 kills
            ]
          }
        }
      }

      {updated_session, _packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 12345}
      )

      quest = updated_session.active_quests[100]
      assert quest.state == :complete  # Auto-completed
      assert Enum.at(quest.objectives, 0).current == 5
    end

    test "does not exceed target count" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 5, target: 5}  # Already at target
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 12345}
      )

      # Should not process since already at target
      quest = updated_session.active_quests[100]
      assert Enum.at(quest.objectives, 0).current == 5
      assert packets == []
    end

    test "skips completed quests" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :complete,  # Already complete
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 5, target: 5}
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 12345}
      )

      assert packets == []
      assert updated_session.active_quests[100].state == :complete
    end
  end

  describe "update_objective/3" do
    test "increments objective by 1 by default" do
      quest = %{
        quest_id: 100,
        state: :accepted,
        dirty: false,
        objectives: [
          %{index: 0, type: 2, data: 12345, current: 2, target: 10}
        ]
      }

      updated = SessionQuestManager.update_objective(quest, 0)

      assert updated.dirty == true
      assert Enum.at(updated.objectives, 0).current == 3
    end

    test "increments objective by custom amount" do
      quest = %{
        quest_id: 100,
        state: :accepted,
        dirty: false,
        objectives: [
          %{index: 0, type: 2, data: 12345, current: 2, target: 10}
        ]
      }

      updated = SessionQuestManager.update_objective(quest, 0, 5)

      assert updated.dirty == true
      assert Enum.at(updated.objectives, 0).current == 7
    end

    test "caps at target value" do
      quest = %{
        quest_id: 100,
        state: :accepted,
        dirty: false,
        objectives: [
          %{index: 0, type: 2, data: 12345, current: 8, target: 10}
        ]
      }

      updated = SessionQuestManager.update_objective(quest, 0, 5)

      # Should cap at 10, not go to 13
      assert Enum.at(updated.objectives, 0).current == 10
    end
  end

  describe "check_quest_completable/1" do
    test "returns true when all objectives complete" do
      quest = %{
        objectives: [
          %{current: 5, target: 5},
          %{current: 10, target: 10}
        ]
      }

      assert SessionQuestManager.check_quest_completable(quest) == true
    end

    test "returns false when any objective incomplete" do
      quest = %{
        objectives: [
          %{current: 5, target: 5},
          %{current: 8, target: 10}  # Not complete
        ]
      }

      assert SessionQuestManager.check_quest_completable(quest) == false
    end

    test "returns true for quest with no objectives" do
      quest = %{objectives: []}

      assert SessionQuestManager.check_quest_completable(quest) == true
    end
  end

  describe "process_game_event/3 with multiple quests" do
    test "updates matching objectives across multiple quests" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 0, target: 5}
            ]
          },
          200 => %{
            quest_id: 200,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 3, target: 10}  # Same creature
            ]
          },
          300 => %{
            quest_id: 300,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 99999, current: 0, target: 5}  # Different creature
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :kill,
        %{creature_id: 12345}
      )

      # Quest 100 and 200 should update
      assert updated_session.active_quests[100].objectives |> Enum.at(0) |> Map.get(:current) == 1
      assert updated_session.active_quests[200].objectives |> Enum.at(0) |> Map.get(:current) == 4

      # Quest 300 should not update
      assert updated_session.active_quests[300].objectives |> Enum.at(0) |> Map.get(:current) == 0

      # Two packets generated
      assert length(packets) == 2
    end
  end

  describe "interact event matching" do
    test "updates interact_object objective" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 12, data: 7890, current: 0, target: 1}  # Interact with object
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :interact,
        %{object_id: 7890}
      )

      quest = updated_session.active_quests[100]
      assert quest.dirty == true
      assert Enum.at(quest.objectives, 0).current == 1
      assert length(packets) == 1
    end
  end

  describe "location event matching" do
    test "updates enter_location objective" do
      session_data = %{
        active_quests: %{
          100 => %{
            quest_id: 100,
            state: :accepted,
            dirty: false,
            objectives: [
              %{index: 0, type: 5, data: 500, current: 0, target: 1}  # Enter location 500
            ]
          }
        }
      }

      {updated_session, packets} = SessionQuestManager.process_game_event(
        session_data,
        :enter_location,
        %{location_id: 500}
      )

      quest = updated_session.active_quests[100]
      assert Enum.at(quest.objectives, 0).current == 1
      assert length(packets) == 1
    end
  end
end
