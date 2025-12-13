defmodule BezgelorWorld.Handler.NpcHandlerDialogueTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Handler.NpcHandler
  alias BezgelorProtocol.Packets.World.{ClientNpcInteract, ServerDialogStart}

  describe "handle_interact/4 with dialogue event" do
    test "sends ServerDialogStart for event 37" do
      # Setup: create a mock connection that captures sent packets
      test_pid = self()

      connection_pid =
        spawn(fn ->
          receive do
            {:send_packet, packet} -> send(test_pid, {:packet_sent, packet})
          end
        end)

      packet = %ClientNpcInteract{npc_guid: 12345, event: 37}
      session_data = %{character_id: 1, zone_instance: nil}

      NpcHandler.handle_interact(connection_pid, 1, packet, session_data)

      assert_receive {:packet_sent, %ServerDialogStart{dialog_unit_id: 12345, unused: false}},
                     1000
    end

    test "sends ServerDialogStart for dialogue event with different GUID" do
      test_pid = self()

      connection_pid =
        spawn(fn ->
          receive do
            {:send_packet, packet} -> send(test_pid, {:packet_sent, packet})
          end
        end)

      packet = %ClientNpcInteract{npc_guid: 99999, event: ClientNpcInteract.event_dialogue()}
      session_data = %{character_id: 42, zone_instance: nil}

      NpcHandler.handle_interact(connection_pid, 42, packet, session_data)

      assert_receive {:packet_sent, %ServerDialogStart{dialog_unit_id: 99999}}, 1000
    end
  end
end
