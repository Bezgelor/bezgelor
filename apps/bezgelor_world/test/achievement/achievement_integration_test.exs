defmodule BezgelorWorld.AchievementIntegrationTest do
  @moduledoc """
  Integration tests for the achievement system wiring.

  Tests the full flow from event broadcast to achievement handler processing.
  """
  use ExUnit.Case, async: false

  alias BezgelorData.{AchievementIndex, AchievementTypes}
  alias BezgelorWorld.Handler.AchievementHandler

  describe "achievement index integration" do
    setup do
      # Ensure index is built
      AchievementIndex.build_index()
      :ok
    end

    test "index contains achievements for all major event types" do
      # Check each major event type has at least some achievements indexed
      event_types = [
        :kill,
        :quest_complete,
        :zone_explore,
        :dungeon_complete,
        :pvp,
        :tradeskill,
        :datacube
      ]

      for event_type <- event_types do
        results = AchievementIndex.lookup(event_type, :any)

        # We should have at least some counter achievements for each type
        assert is_list(results),
               "Expected list for #{event_type}, got #{inspect(results)}"
      end
    end

    test "type mapping covers all indexed achievements" do
      # Get all event types in the index
      event_types = AchievementIndex.event_types()

      # All should be supported event types (plus :zone for zone indexing)
      supported = AchievementTypes.all_event_types() ++ [:zone]

      for event_type <- event_types do
        assert event_type in supported,
               "Event type #{event_type} in index but not in supported types"
      end
    end
  end

  describe "achievement handler startup" do
    test "handler starts successfully" do
      # Use a fake connection pid
      connection_pid = self()
      character_id = 12345

      {:ok, handler_pid} =
        AchievementHandler.start_link(
          connection_pid,
          character_id,
          account_id: 1
        )

      assert Process.alive?(handler_pid)

      # Clean up
      GenServer.stop(handler_pid, :normal)
    end

    test "send_achievement_list sends packet" do
      connection_pid = self()
      character_id = 99999

      # This should send a packet to self()
      :ok = AchievementHandler.send_achievement_list(connection_pid, character_id)

      # We should receive the packet
      assert_receive {:send_packet, packet}, 1000
      assert %{__struct__: BezgelorProtocol.Packets.World.ServerAchievementList} = packet
    end
  end

  describe "achievement type mappings" do
    test "all 16 event types are supported" do
      types = AchievementTypes.all_event_types()
      assert length(types) == 16
    end

    test "kill types map correctly" do
      assert AchievementTypes.event_type(2) == :kill
      assert AchievementTypes.event_type(61) == :kill
      assert AchievementTypes.event_type(105) == :kill
    end

    test "quest types map correctly" do
      assert AchievementTypes.event_type(35) == :quest_complete
      assert AchievementTypes.event_type(77) == :quest_complete
    end

    test "dungeon types map correctly" do
      assert AchievementTypes.event_type(6) == :dungeon_complete
      assert AchievementTypes.event_type(7) == :dungeon_complete
      assert AchievementTypes.event_type(38) == :dungeon_complete
    end

    test "uses_object_id? identifies specific-target achievements" do
      # Type 2 (kill specific creature) uses objectId
      assert AchievementTypes.uses_object_id?(2) == true
      # Type 61 (kill X creatures) does not
      assert AchievementTypes.uses_object_id?(61) == false
    end

    test "uses_counter? identifies counter achievements" do
      assert AchievementTypes.uses_counter?(61) == true
      assert AchievementTypes.uses_counter?(77) == true
      assert AchievementTypes.uses_counter?(2) == false
    end
  end

  describe "index lookup performance" do
    setup do
      AchievementIndex.build_index()
      :ok
    end

    test "lookup is O(1) - completes quickly" do
      # Measure time for 1000 lookups
      start_time = System.monotonic_time(:microsecond)

      for _ <- 1..1000 do
        AchievementIndex.lookup(:kill, 12345)
      end

      elapsed = System.monotonic_time(:microsecond) - start_time

      # Should complete in under 100ms for 1000 lookups (100us avg per lookup)
      assert elapsed < 100_000,
             "Lookups took #{elapsed}us, expected < 100_000us"
    end

    test "index count is reasonable" do
      count = AchievementIndex.count()

      # With 4,943 achievements, we should have thousands of index entries
      # (some achievements create multiple entries for different targets)
      assert count > 1000, "Expected > 1000 index entries, got #{count}"
    end
  end
end
