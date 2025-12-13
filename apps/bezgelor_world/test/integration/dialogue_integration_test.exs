defmodule BezgelorWorld.Integration.DialogueIntegrationTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.GossipManager
  alias BezgelorWorld.Handler.NpcHandler
  alias BezgelorProtocol.Packets.World.{ClientNpcInteract, ServerDialogStart, ServerChatNpc}

  @moduletag :integration

  describe "dialogue system integration" do
    test "full flow: NPC click sends dialog start" do
      test_pid = self()

      connection_pid =
        spawn(fn ->
          receive do
            {:send_packet, packet} -> send(test_pid, {:packet_sent, packet})
          end
        end)

      # Use a test NPC GUID with dialogue event
      packet = %ClientNpcInteract{npc_guid: 1000, event: 37}
      session_data = %{character_id: 1, zone_instance: nil}

      NpcHandler.handle_interact(connection_pid, 1, packet, session_data)

      assert_receive {:packet_sent, %ServerDialogStart{dialog_unit_id: 1000}}, 1000
    end

    test "NPC click with vendor event does not send dialog start" do
      test_pid = self()

      connection_pid =
        spawn(fn ->
          receive do
            {:send_packet, packet} -> send(test_pid, {:packet_sent, packet})
          after
            100 -> send(test_pid, :timeout)
          end
        end)

      # Event 49 = vendor, should not trigger DialogStart
      packet = %ClientNpcInteract{npc_guid: 2000, event: 49}
      session_data = %{character_id: 1, zone_instance: nil}

      NpcHandler.handle_interact(connection_pid, 1, packet, session_data)

      # Should not receive DialogStart for vendor event
      refute_receive {:packet_sent, %ServerDialogStart{}}, 200
    end

    test "gossip manager builds valid packet" do
      creature = %{localizedTextIdName: 12345}
      entry = %{localizedTextId: 67890}

      packet = GossipManager.build_gossip_packet(creature, entry)

      assert %ServerChatNpc{} = packet
      assert packet.unit_name_text_id == 12345
      assert packet.message_text_id == 67890
      assert packet.channel_type == ServerChatNpc.npc_say()
    end

    test "gossip manager respects proximity enum 0 (click-only)" do
      gossip_set = %{gossipProximityEnum: 0, cooldown: 0}

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          {100.0, 0.0, 100.0},
          {101.0, 0.0, 101.0},
          nil
        )

      assert result == false
    end

    test "gossip manager triggers for proximity enum 1 within range" do
      gossip_set = %{gossipProximityEnum: 1, cooldown: 0}
      # Player is ~7 units away, within 15-unit range
      npc_pos = {100.0, 0.0, 100.0}
      player_pos = {105.0, 0.0, 105.0}

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          npc_pos,
          player_pos,
          nil
        )

      assert result == true
    end

    test "gossip manager respects cooldown" do
      gossip_set = %{gossipProximityEnum: 1, cooldown: 60}
      now = System.system_time(:second)
      # Triggered 30 seconds ago, still on 60-second cooldown
      last_trigger = now - 30

      result =
        GossipManager.should_trigger_proximity?(
          gossip_set,
          {0.0, 0.0, 0.0},
          {1.0, 0.0, 1.0},
          last_trigger
        )

      assert result == false
    end

    test "gossip entry selection returns nil for empty list" do
      result = GossipManager.select_gossip_entry([], [%{id: 1}])
      assert result == nil
    end

    test "gossip entry selection returns entry from non-empty list" do
      entries = [
        %{id: 1, localizedTextId: 100, prerequisiteId: 0},
        %{id: 2, localizedTextId: 101, prerequisiteId: 0}
      ]

      result = GossipManager.select_gossip_entry(entries, [%{id: 1}])

      assert result in entries
    end
  end
end
