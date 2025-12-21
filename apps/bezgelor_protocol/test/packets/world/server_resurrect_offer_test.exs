defmodule BezgelorProtocol.Packets.World.ServerResurrectOfferTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerResurrectOffer
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes resurrection offer packet successfully" do
      packet = %ServerResurrectOffer{
        caster_guid: 0x1000000000000002,
        caster_name: "Healer",
        spell_id: 12345,
        health_percent: 35.0,
        timeout_ms: 60_000
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerResurrectOffer.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Should produce non-empty binary output
      assert byte_size(binary) > 0
    end

    test "serializes caster guid at start of packet" do
      caster_guid = 0x1000000000000123

      packet = %ServerResurrectOffer{
        caster_guid: caster_guid,
        caster_name: "Test",
        spell_id: 1,
        health_percent: 50.0,
        timeout_ms: 30_000
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerResurrectOffer.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # GUID is first field - 8 bytes little endian
      <<read_guid::little-64, _rest::binary>> = binary
      assert read_guid == caster_guid
    end

    test "includes caster name in output" do
      packet = %ServerResurrectOffer{
        caster_guid: 1,
        caster_name: "TestHealer",
        spell_id: 1,
        health_percent: 35.0,
        timeout_ms: 60_000
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerResurrectOffer.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # "TestHealer" in UTF-16LE should contain these bytes
      # T=0x54, e=0x65, s=0x73, t=0x74, H=0x48, etc.
      # "T" in UTF-16LE
      assert :binary.match(binary, <<0x54, 0x00>>) != :nomatch
    end

    test "handles empty caster name" do
      packet = %ServerResurrectOffer{
        caster_guid: 1,
        caster_name: "",
        spell_id: 99999,
        health_percent: 35.0,
        timeout_ms: 60_000
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerResurrectOffer.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Should still produce valid output
      assert byte_size(binary) > 8
    end

    test "different health percentages produce different output" do
      packet1 = %ServerResurrectOffer{
        caster_guid: 1,
        caster_name: "",
        spell_id: 1,
        health_percent: 35.0,
        timeout_ms: 60_000
      }

      packet2 = %ServerResurrectOffer{
        caster_guid: 1,
        caster_name: "",
        spell_id: 1,
        health_percent: 60.0,
        timeout_ms: 60_000
      }

      writer1 = PacketWriter.new()
      {:ok, writer1} = ServerResurrectOffer.write(packet1, writer1)
      binary1 = PacketWriter.to_binary(writer1)

      writer2 = PacketWriter.new()
      {:ok, writer2} = ServerResurrectOffer.write(packet2, writer2)
      binary2 = PacketWriter.to_binary(writer2)

      # Different health percentages should produce different output
      assert binary1 != binary2
    end
  end

  describe "new/5" do
    test "creates packet with correct values" do
      packet =
        ServerResurrectOffer.new(
          0x1000000000000002,
          "Medic",
          12345,
          35.0,
          60_000
        )

      assert packet.caster_guid == 0x1000000000000002
      assert packet.caster_name == "Medic"
      assert packet.spell_id == 12345
      assert packet.health_percent == 35.0
      assert packet.timeout_ms == 60_000
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerResurrectOffer.opcode() == :server_resurrect_offer
    end
  end
end
