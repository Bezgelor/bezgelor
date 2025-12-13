defmodule BezgelorProtocol.Packets.World.ClientNpcInteractTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientNpcInteract
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "parses NPC interact with dialogue event" do
      # guid (32 bits) + event byte (7 bits LSB = 37 = 0b0100101)
      # Event 37 stored in LSB of byte = 0x25
      data = <<12345::little-32, 37::8>>
      reader = PacketReader.new(data)

      {:ok, packet, _reader} = ClientNpcInteract.read(reader)

      assert packet.npc_guid == 12345
      assert packet.event == 37
    end

    test "parses vendor event" do
      # Event 49 = 0b0110001, stored as byte 0x31
      data = <<99999::little-32, 49::8>>
      reader = PacketReader.new(data)

      {:ok, packet, _reader} = ClientNpcInteract.read(reader)

      assert packet.npc_guid == 99999
      assert packet.event == 49
    end

    test "parses taxi event" do
      # Event 48 = 0b0110000, stored as byte 0x30
      data = <<55555::little-32, 48::8>>
      reader = PacketReader.new(data)

      {:ok, packet, _reader} = ClientNpcInteract.read(reader)

      assert packet.npc_guid == 55555
      assert packet.event == 48
    end
  end

  describe "event type helpers" do
    test "event_dialogue returns 37" do
      assert ClientNpcInteract.event_dialogue() == 37
    end

    test "event_vendor returns 49" do
      assert ClientNpcInteract.event_vendor() == 49
    end

    test "event_taxi returns 48" do
      assert ClientNpcInteract.event_taxi() == 48
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ClientNpcInteract.opcode() == :client_npc_interact
    end
  end
end
