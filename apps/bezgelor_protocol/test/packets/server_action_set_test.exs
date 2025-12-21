defmodule BezgelorProtocol.Packets.World.ServerActionSetTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerActionSet
  alias BezgelorProtocol.PacketWriter

  @moduledoc """
  Tests for ServerActionSet packet serialization.

  Verifies that our packet output matches NexusForever's expected format.
  """

  describe "write/2" do
    test "serializes a simple action set with one spell" do
      # Spellslinger Pistol Shot at slot 0
      packet = %ServerActionSet{
        spec_index: 0,
        unlocked: true,
        result: :ok,
        actions: [
          %{type: :spell, object_id: 435, slot: 0, ui_location: 0}
        ]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerActionSet.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Dump bytes for debugging
      IO.puts("\n=== ServerActionSet Packet Dump ===")
      IO.puts("Total bytes: #{byte_size(binary)}")
      IO.puts("Hex dump:")

      for {byte, idx} <- Enum.with_index(:binary.bin_to_list(binary)) do
        IO.write("#{String.pad_leading(Integer.to_string(byte, 16), 2, "0")} ")
        if rem(idx + 1, 16) == 0, do: IO.puts("")
      end

      IO.puts("")

      # Expected structure (bit-packed):
      # Header (17 bits):
      #   spec_index: 3 bits = 0
      #   unlocked: 2 bits = 1
      #   result: 6 bits = 0
      #   action_count: 6 bits = 48
      #
      # First action (77 bits):
      #   shortcut_type: 4 bits = 4 (SpellbookItem)
      #   location: 9 bits = 4 (InventoryLocation.Ability)
      #   bag_index: 32 bits = 0
      #   object_id: 32 bits = 435
      #
      # Remaining 47 empty actions (77 bits each):
      #   shortcut_type: 4 bits = 0 (None)
      #   location: 9 bits = 300 (empty marker)
      #   bag_index: 32 bits = slot number
      #   object_id: 32 bits = 0

      # Verify the header starts correctly
      # First byte contains: spec_index(3) + unlocked(2) + first 3 bits of result(6)
      # spec_index=0 (000), unlocked=1 (01), result first 3 bits=0 (000) = 0b000_01_000 = 0x08
      first_byte = :binary.at(binary, 0)
      IO.puts("First byte: 0x#{Integer.to_string(first_byte, 16)}")

      # Expected:
      # bits 0-2: spec_index = 0
      # bits 3-4: unlocked = 1
      # bits 5-7: result bits 0-2 = 0
      # So first byte = 0b000_01_000 in little-endian bit order
      # Actually in LSB-first: bit0-2 = spec (0), bit3-4 = unlocked (1), bit5-7 = result low (0)
      # = 0b00001000 = 8
      assert first_byte == 8, "Expected first byte to be 8 (spec=0, unlocked=1)"

      # The packet should have content
      assert byte_size(binary) > 0
    end

    test "serializes action set with two spells at slots 0 and 1" do
      # Spellslinger abilities: Pistol Shot (435) at slot 0, Quick Draw (27638) at slot 1
      packet = %ServerActionSet{
        spec_index: 0,
        unlocked: true,
        result: :ok,
        actions: [
          %{type: :spell, object_id: 435, slot: 0, ui_location: 0},
          %{type: :spell, object_id: 27638, slot: 1, ui_location: 1}
        ]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerActionSet.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      IO.puts("\n=== Two Spell Action Set Dump ===")
      IO.puts("Total bytes: #{byte_size(binary)}")

      # Dump first 32 bytes (should contain header + first 2 actions)
      IO.puts("First 32 bytes (hex):")

      binary
      |> :binary.bin_to_list()
      |> Enum.take(32)
      |> Enum.with_index()
      |> Enum.each(fn {byte, idx} ->
        IO.write("#{String.pad_leading(Integer.to_string(byte, 16), 2, "0")} ")
        if rem(idx + 1, 16) == 0, do: IO.puts("")
      end)

      IO.puts("")

      # Verify packet has expected size
      # Header: 17 bits
      # 48 actions * 77 bits = 3696 bits
      # Total: 3713 bits = 464.125 bytes -> rounds up to 465 bytes
      # Ceiling division
      expected_size = div(17 + 48 * 77 + 7, 8)
      IO.puts("Expected size: #{expected_size} bytes, Actual: #{byte_size(binary)} bytes")
      assert byte_size(binary) == expected_size
    end
  end
end
