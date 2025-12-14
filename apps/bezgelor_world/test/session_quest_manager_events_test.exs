defmodule BezgelorWorld.Quest.SessionQuestManagerEventsTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Quest.SessionQuestManager

  describe "process_game_event/3 with :enter_area" do
    test "updates objective when entering matching area" do
      # Create a session with an active quest that has a type 5 (enter_location) objective
      session_data = %{
        active_quests: %{
          1001 => %{
            quest_id: 1001,
            state: :accepted,
            dirty: false,
            objectives: [
              %{
                index: 0,
                type: 5,
                data: 50231,  # World location ID to enter
                target: 1,
                current: 0
              }
            ]
          }
        }
      }

      # Simulate entering the area (trigger volume)
      {updated_session, packets} =
        SessionQuestManager.process_game_event(session_data, :enter_area, %{
          area_id: 50231,
          zone_id: 4844
        })

      # Quest objective should be updated
      quest = updated_session[:active_quests][1001]
      objective = Enum.find(quest.objectives, &(&1.index == 0))

      assert objective.current == 1
      assert quest.state == :complete  # All objectives done
      assert packets != []  # Update packet sent
    end

    test "does not update objective for non-matching area" do
      session_data = %{
        active_quests: %{
          1001 => %{
            quest_id: 1001,
            state: :accepted,
            dirty: false,
            objectives: [
              %{
                index: 0,
                type: 5,
                data: 50231,
                target: 1,
                current: 0
              }
            ]
          }
        }
      }

      # Enter a different area
      {updated_session, packets} =
        SessionQuestManager.process_game_event(session_data, :enter_area, %{
          area_id: 99999,
          zone_id: 4844
        })

      # Quest should not be updated
      quest = updated_session[:active_quests][1001]
      objective = Enum.find(quest.objectives, &(&1.index == 0))

      assert objective.current == 0
      assert packets == []
    end
  end

  describe "process_game_event/3 with :enter_zone" do
    test "updates objective when entering matching zone" do
      session_data = %{
        active_quests: %{
          1002 => %{
            quest_id: 1002,
            state: :accepted,
            dirty: false,
            objectives: [
              %{
                index: 0,
                type: 5,
                data: 4844,  # Zone ID to enter
                target: 1,
                current: 0
              }
            ]
          }
        }
      }

      {updated_session, packets} =
        SessionQuestManager.process_game_event(session_data, :enter_zone, %{
          world_id: 1634,
          zone_id: 4844
        })

      quest = updated_session[:active_quests][1002]
      objective = Enum.find(quest.objectives, &(&1.index == 0))

      assert objective.current == 1
      assert packets != []
    end
  end
end
