defmodule BezgelorWorld.GossipManagerTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.GossipManager

  describe "select_gossip_entry/2" do
    test "returns random entry from valid entries" do
      entries = [
        %{id: 1, localizedTextId: 100, prerequisiteId: 0, indexOrder: 0},
        %{id: 2, localizedTextId: 101, prerequisiteId: 0, indexOrder: 1}
      ]

      player = %{id: 1, level: 10}

      result = GossipManager.select_gossip_entry(entries, [player])

      assert result in entries
    end

    test "returns nil for empty entries" do
      result = GossipManager.select_gossip_entry([], [%{id: 1}])

      assert result == nil
    end

    test "returns entry with prerequisite when players provided" do
      entries = [
        %{id: 1, localizedTextId: 100, prerequisiteId: 999, indexOrder: 0}
      ]

      player = %{id: 1, level: 50}

      result = GossipManager.select_gossip_entry(entries, [player])

      # For now, all prerequisites are considered met
      assert result == hd(entries)
    end
  end

  describe "should_trigger_proximity?/4" do
    test "returns true when player in range and no cooldown" do
      gossip_set = %{gossipProximityEnum: 1, cooldown: 0}
      npc_position = {100.0, 0.0, 100.0}
      # ~7 units away
      player_position = {105.0, 0.0, 105.0}

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          npc_position,
          player_position,
          _last_trigger = nil
        )

      assert result == true
    end

    test "returns false when gossipProximityEnum is 0 (click-only)" do
      gossip_set = %{gossipProximityEnum: 0, cooldown: 0}

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          {0.0, 0.0, 0.0},
          {1.0, 0.0, 1.0},
          nil
        )

      assert result == false
    end

    test "returns false when player out of range" do
      # range 15
      gossip_set = %{gossipProximityEnum: 1, cooldown: 0}
      npc_position = {100.0, 0.0, 100.0}
      # ~141 units away
      player_position = {200.0, 0.0, 200.0}

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          npc_position,
          player_position,
          nil
        )

      assert result == false
    end

    test "returns false when on cooldown" do
      gossip_set = %{gossipProximityEnum: 1, cooldown: 30}
      now = System.system_time(:second)
      # 10 seconds ago, cooldown is 30
      last_trigger = now - 10

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          {0.0, 0.0, 0.0},
          {1.0, 0.0, 1.0},
          last_trigger
        )

      assert result == false
    end

    test "returns true when cooldown has passed" do
      gossip_set = %{gossipProximityEnum: 1, cooldown: 30}
      now = System.system_time(:second)
      # 60 seconds ago, cooldown is 30
      last_trigger = now - 60

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          {0.0, 0.0, 0.0},
          {1.0, 0.0, 1.0},
          last_trigger
        )

      assert result == true
    end
  end

  describe "build_gossip_packet/2" do
    test "creates ServerChatNpc packet with correct text IDs" do
      creature = %{localizedTextIdName: 12345}
      entry = %{localizedTextId: 67890}

      packet = GossipManager.build_gossip_packet(creature, entry)

      assert packet.__struct__ == BezgelorProtocol.Packets.World.ServerChatNpc
      assert packet.unit_name_text_id == 12345
      assert packet.message_text_id == 67890
      assert packet.channel_type == 24
    end

    test "uses default 0 when creature has no localizedTextIdName" do
      creature = %{}
      entry = %{localizedTextId: 99999}

      packet = GossipManager.build_gossip_packet(creature, entry)

      assert packet.unit_name_text_id == 0
      assert packet.message_text_id == 99999
    end
  end

  describe "get_proximity_range/1" do
    test "returns nil for click-only (enum 0)" do
      assert GossipManager.get_proximity_range(0) == nil
    end

    test "returns 15.0 for close range (enum 1)" do
      assert GossipManager.get_proximity_range(1) == 15.0
    end

    test "returns 30.0 for medium range (enum 2)" do
      assert GossipManager.get_proximity_range(2) == 30.0
    end
  end
end
