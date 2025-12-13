defmodule BezgelorProtocol.Packets.World.ServerDialogStartTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerDialogStart
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "serializes dialog start packet" do
      packet = %ServerDialogStart{
        dialog_unit_id: 12345,
        unused: false
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerDialogStart.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # uint32 little-endian + bool
      assert data == <<12345::little-32, 0::8>>
    end

    test "serializes with unused flag true" do
      packet = %ServerDialogStart{
        dialog_unit_id: 0xFFFFFFFF,
        unused: true
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerDialogStart.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert data == <<0xFFFFFFFF::little-32, 1::8>>
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerDialogStart.opcode() == :server_dialog_start
    end
  end
end
