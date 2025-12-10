defmodule BezgelorProtocol.Packets.World.BuffPacketsTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.{ServerBuffApply, ServerBuffRemove}
  alias BezgelorProtocol.PacketWriter

  describe "ServerBuffApply" do
    test "opcode returns :server_buff_apply" do
      assert ServerBuffApply.opcode() == :server_buff_apply
    end

    test "writes buff application packet" do
      packet = %ServerBuffApply{
        target_guid: 12345,
        caster_guid: 67890,
        buff_id: 1,
        spell_id: 4,
        buff_type: 0,
        amount: 100,
        duration: 10_000,
        is_debuff: false
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerBuffApply.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # uint64 target + uint64 caster + uint32 buff_id + uint32 spell_id +
      # uint8 buff_type + int32 amount + uint32 duration + uint8 is_debuff
      assert byte_size(binary) == 8 + 8 + 4 + 4 + 1 + 4 + 4 + 1
    end

    test "new/8 creates packet struct" do
      packet = ServerBuffApply.new(12345, 67890, 1, 4, :absorb, 100, 10_000, false)

      assert packet.target_guid == 12345
      assert packet.caster_guid == 67890
      assert packet.buff_id == 1
      assert packet.spell_id == 4
      assert packet.buff_type == 0
      assert packet.amount == 100
      assert packet.duration == 10_000
      assert packet.is_debuff == false
    end
  end

  describe "ServerBuffRemove" do
    test "opcode returns :server_buff_remove" do
      assert ServerBuffRemove.opcode() == :server_buff_remove
    end

    test "writes buff removal packet" do
      packet = %ServerBuffRemove{
        target_guid: 12345,
        buff_id: 1,
        reason: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerBuffRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # uint64 target + uint32 buff_id + uint8 reason
      assert byte_size(binary) == 8 + 4 + 1
    end

    test "new/3 creates packet struct" do
      packet = ServerBuffRemove.new(12345, 1, :expired)

      assert packet.target_guid == 12345
      assert packet.buff_id == 1
      assert packet.reason == 1
    end
  end
end
