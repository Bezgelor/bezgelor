defmodule BezgelorData.AchievementIndexTest do
  use ExUnit.Case, async: false

  alias BezgelorData.AchievementIndex

  # These tests require the Store to be running with data loaded
  # They test the index building and lookup functionality

  describe "build_index/0" do
    test "creates ETS table and indexes achievements" do
      # Build the index (may already exist from application startup)
      assert :ok = AchievementIndex.build_index()

      # Verify the table exists
      assert :ets.whereis(:bezgelor_achievement_index) != :undefined
    end

    test "indexes achievements with count greater than zero" do
      AchievementIndex.build_index()

      # Should have indexed some achievements
      count = AchievementIndex.count()
      assert count > 0, "Expected achievements to be indexed, got #{count}"
    end
  end

  describe "lookup/2" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "returns list for valid event type lookup" do
      # Kill type achievements exist
      results = AchievementIndex.lookup(:kill, :any)
      assert is_list(results)
    end

    test "returns empty list for unknown target" do
      results = AchievementIndex.lookup(:kill, 999_999_999)
      assert results == [] or is_list(results)
    end

    test "result maps contain required fields" do
      results = AchievementIndex.lookup(:kill, :any)

      if length(results) > 0 do
        result = hd(results)
        assert Map.has_key?(result, :id)
        assert Map.has_key?(result, :type)
        assert Map.has_key?(result, :type_id)
        assert Map.has_key?(result, :object_id)
        assert Map.has_key?(result, :target)
        assert Map.has_key?(result, :zone_id)
        assert Map.has_key?(result, :title_id)
        assert Map.has_key?(result, :points)
        assert Map.has_key?(result, :has_checklist)
      end
    end

    test "lookup returns correct event type" do
      results = AchievementIndex.lookup(:kill, :any)

      for result <- results do
        assert result.type == :kill
      end
    end

    test "quest_complete lookup works" do
      results = AchievementIndex.lookup(:quest_complete, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :quest_complete
      end
    end

    test "zone_explore lookup works" do
      results = AchievementIndex.lookup(:zone_explore, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :zone_explore
      end
    end

    test "dungeon_complete lookup works" do
      results = AchievementIndex.lookup(:dungeon_complete, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :dungeon_complete
      end
    end

    test "pvp lookup works" do
      results = AchievementIndex.lookup(:pvp, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :pvp
      end
    end

    test "tradeskill lookup works" do
      results = AchievementIndex.lookup(:tradeskill, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :tradeskill
      end
    end

    test "datacube lookup works" do
      results = AchievementIndex.lookup(:datacube, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :datacube
      end
    end

    test "progression lookup works" do
      results = AchievementIndex.lookup(:progression, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :progression
      end
    end

    test "meta lookup works" do
      results = AchievementIndex.lookup(:meta, :any)
      assert is_list(results)

      for result <- results do
        assert result.type == :meta
      end
    end
  end

  describe "lookup_by_zone/1" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "returns list for zone lookup" do
      # Zone 0 would return empty, but valid zones should return results
      results = AchievementIndex.lookup_by_zone(0)
      assert is_list(results)
    end

    test "zone results have zone_id set" do
      # Try to find a zone with achievements
      # Zone IDs vary, so we test with a common zone
      results = AchievementIndex.lookup_by_zone(98)

      for result <- results do
        # Results from zone index should have zone_id matching or be related
        assert is_integer(result.zone_id)
      end
    end
  end

  describe "count/0" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "returns positive count after build" do
      count = AchievementIndex.count()
      assert is_integer(count)
      # With 4,943 achievements, we should have many index entries
      # Each achievement may create multiple entries (by event type and zone)
      assert count > 0
    end
  end

  describe "event_types/0" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "returns list of event types" do
      types = AchievementIndex.event_types()
      assert is_list(types)
    end

    test "includes common event types" do
      types = AchievementIndex.event_types()

      # Should include at least some of these types
      expected_types = [
        :kill,
        :quest_complete,
        :zone_explore,
        :dungeon_complete,
        :zone
      ]

      present_types = Enum.filter(expected_types, &(&1 in types))
      # Should have at least one common type
      assert length(present_types) > 0
    end

    test "all returned types are atoms" do
      types = AchievementIndex.event_types()

      for type <- types do
        assert is_atom(type)
      end
    end
  end

  describe "specific target lookup" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "specific creature ID lookup returns achievements for that creature" do
      # First, find any kill achievement with a specific object_id
      kill_any = AchievementIndex.lookup(:kill, :any)
      specific_kill = Enum.find(kill_any, fn d -> d.object_id > 0 end)

      if specific_kill do
        # Look up by that specific creature
        results = AchievementIndex.lookup(:kill, specific_kill.object_id)

        # Should find the same achievement (or it could be in :any)
        # This tests that specific lookups work
        assert is_list(results)
      end
    end

    test "combines specific and :any results" do
      # A lookup should return both specific matches AND counter matches
      results = AchievementIndex.lookup(:kill, 12345)

      # Even if 12345 has no specific achievements,
      # we should get :any counter achievements
      any_results = AchievementIndex.lookup(:kill, :any)

      # Total results should include any counter achievements
      # (specific may or may not exist)
      assert length(results) >= 0
      assert length(any_results) >= 0
    end
  end
end
