defmodule BezgelorWorld.Quest.QuestCacheTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Quest.QuestCache

  describe "from_session_format/1" do
    test "converts session quest to database format" do
      session_quest = %{
        quest_id: 123,
        state: :accepted,
        accepted_at: ~U[2025-12-12 10:00:00Z],
        dirty: true,
        objectives: [
          %{index: 0, type: 2, data: 12345, current: 3, target: 10},
          %{index: 1, type: 3, data: 67890, current: 0, target: 5}
        ]
      }

      result = QuestCache.from_session_format(session_quest)

      assert result.quest_id == 123
      assert result.state == :accepted
      assert result.progress["objectives"] |> length() == 2

      [obj1, obj2] = result.progress["objectives"]
      assert obj1["index"] == 0
      assert obj1["current"] == 3
      assert obj1["target"] == 10
      assert obj2["index"] == 1
      assert obj2["current"] == 0
    end
  end

  describe "mark_dirty/2" do
    test "marks a quest as dirty" do
      active_quests = %{
        123 => %{
          quest_id: 123,
          state: :accepted,
          accepted_at: ~U[2025-12-12 10:00:00Z],
          dirty: false,
          objectives: []
        }
      }

      result = QuestCache.mark_dirty(active_quests, 123)

      assert result[123].dirty == true
    end

    test "returns unchanged map for non-existent quest" do
      active_quests = %{}

      result = QuestCache.mark_dirty(active_quests, 999)

      assert result == %{}
    end
  end

  describe "get_dirty_quests/1" do
    test "returns only dirty quests" do
      active_quests = %{
        123 => %{quest_id: 123, dirty: true, objectives: []},
        124 => %{quest_id: 124, dirty: false, objectives: []},
        125 => %{quest_id: 125, dirty: true, objectives: []}
      }

      result = QuestCache.get_dirty_quests(active_quests)

      assert length(result) == 2
      quest_ids = Enum.map(result, & &1.quest_id)
      assert 123 in quest_ids
      assert 125 in quest_ids
    end

    test "returns empty list when no dirty quests" do
      active_quests = %{
        123 => %{quest_id: 123, dirty: false, objectives: []}
      }

      result = QuestCache.get_dirty_quests(active_quests)

      assert result == []
    end
  end

  describe "clear_dirty_flags/1" do
    test "clears all dirty flags" do
      active_quests = %{
        123 => %{quest_id: 123, dirty: true, objectives: []},
        124 => %{quest_id: 124, dirty: true, objectives: []}
      }

      result = QuestCache.clear_dirty_flags(active_quests)

      assert result[123].dirty == false
      assert result[124].dirty == false
    end
  end
end
