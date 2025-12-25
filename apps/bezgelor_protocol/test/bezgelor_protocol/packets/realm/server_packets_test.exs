defmodule BezgelorProtocol.Packets.Realm.ServerPacketsTest do
  @moduledoc """
  Tests for realm server packets.

  Note: wide_string uses bit-packed format (1-bit extended + 7/15-bit length + UTF-16LE data).
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.Realm.{
    ServerAuthAccepted,
    ServerAuthDenied,
    ServerRealmMessages,
    ServerRealmInfo
  }

  alias BezgelorProtocol.PacketWriter

  describe "ServerAuthAccepted" do
    test "opcode/0 returns correct opcode" do
      assert ServerAuthAccepted.opcode() == :server_auth_accepted_realm
    end

    test "write/2 serializes packet correctly" do
      packet = %ServerAuthAccepted{disconnected_for_lag: 0}
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerAuthAccepted.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      assert <<0::little-32>> = binary
    end

    test "write/2 handles non-zero lag flag" do
      packet = %ServerAuthAccepted{disconnected_for_lag: 1}
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerAuthAccepted.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      assert <<1::little-32>> = binary
    end
  end

  describe "ServerAuthDenied" do
    test "opcode/0 returns correct opcode" do
      assert ServerAuthDenied.opcode() == :server_auth_denied_realm
    end

    test "write/2 serializes invalid_token denial" do
      packet = %ServerAuthDenied{
        result: :invalid_token,
        error_value: 0,
        suspended_days: 0.0
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerAuthDenied.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      <<result::little-32, error::little-32, days::little-float-32>> = binary
      assert result == 16
      assert error == 0
      assert days == 0.0
    end

    test "write/2 serializes account_suspended with days" do
      packet = %ServerAuthDenied{
        result: :account_suspended,
        error_value: 0,
        suspended_days: 7.5
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerAuthDenied.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      <<result::little-32, error::little-32, days::little-float-32>> = binary
      assert result == 21
      assert error == 0
      assert days == 7.5
    end

    test "write/2 serializes no_realms_available" do
      packet = %ServerAuthDenied{
        result: :no_realms_available,
        error_value: 0,
        suspended_days: 0.0
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerAuthDenied.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      <<result::little-32, error::little-32, days::little-float-32>> = binary
      assert result == 18
      assert error == 0
      assert days == 0.0
    end

    test "result_code/1 returns correct codes" do
      assert ServerAuthDenied.result_code(:unknown) == 0
      assert ServerAuthDenied.result_code(:invalid_token) == 16
      assert ServerAuthDenied.result_code(:no_realms_available) == 18
      assert ServerAuthDenied.result_code(:version_mismatch) == 19
      assert ServerAuthDenied.result_code(:account_banned) == 20
      assert ServerAuthDenied.result_code(:account_suspended) == 21
    end
  end

  describe "ServerRealmMessages" do
    test "opcode/0 returns correct opcode" do
      assert ServerRealmMessages.opcode() == :server_realm_messages
    end

    test "write/2 serializes empty message list" do
      packet = %ServerRealmMessages{messages: []}
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerRealmMessages.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      assert <<0::little-32>> = binary
    end

    test "write/2 serializes single message" do
      packet = %ServerRealmMessages{
        messages: [
          %ServerRealmMessages.Message{index: 0, message: "Hi"}
        ]
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerRealmMessages.write(packet, writer)

      binary = PacketWriter.to_binary(writer)

      # Parse: count (uint32) + index (uint32) + wide_string (bit-packed)
      <<count::little-32, index::little-32, rest::binary>> = binary

      assert count == 1
      assert index == 0

      # Parse bit-packed wide string
      {message, _remaining} = parse_wide_string(rest)
      assert message == "Hi"
    end

    test "write/2 serializes multiple messages" do
      packet = %ServerRealmMessages{
        messages: [
          %ServerRealmMessages.Message{index: 0, message: "A"},
          %ServerRealmMessages.Message{index: 1, message: "B"}
        ]
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerRealmMessages.write(packet, writer)

      binary = PacketWriter.to_binary(writer)
      <<count::little-32, _rest::binary>> = binary
      assert count == 2
    end
  end

  describe "ServerRealmInfo" do
    test "opcode/0 returns correct opcode" do
      assert ServerRealmInfo.opcode() == :server_realm_info
    end

    test "write/2 serializes complete realm info" do
      session_key = :crypto.strong_rand_bytes(16)

      packet = %ServerRealmInfo{
        address: ServerRealmInfo.ip_to_uint32("127.0.0.1"),
        port: 24000,
        session_key: session_key,
        account_id: 42,
        realm_name: "Test",
        flags: 0,
        type: :pve,
        note_text_id: 0
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerRealmInfo.write(packet, writer)

      binary = PacketWriter.to_binary(writer)

      # Parse: address (u32 little) + port (u16) + session_key (16 bytes) +
      #        account_id (u32) + realm_name (bit-packed wide_string) +
      #        flags (u32) + type (2 bits) + note_text_id (21 bits)
      <<
        addr::little-32,
        port::little-16,
        key::binary-size(16),
        account_id::little-32,
        rest::binary
      >> = binary

      # Address stored as big-endian uint32 value (0x7F000001 for 127.0.0.1)
      # but written as little-endian, so we read it back as little-endian
      assert addr == ServerRealmInfo.ip_to_uint32("127.0.0.1")
      assert port == 24000
      assert key == session_key
      assert account_id == 42

      # Parse bit-packed wide string for realm_name
      {name, after_name} = parse_wide_string(rest)
      assert name == "Test"

      # Remaining: flags (u32) + type_and_note bits (padded to byte boundary)
      <<flags::little-32, type_bits::little-size(24)>> = after_name

      assert flags == 0

      # Type is 2 bits, note_text_id is 21 bits, total 23 bits padded to 3 bytes
      type_val = type_bits &&& 0x3
      assert type_val == 0
    end

    test "write/2 serializes pvp realm type" do
      session_key = :crypto.strong_rand_bytes(16)

      packet = %ServerRealmInfo{
        address: 0,
        port: 24000,
        session_key: session_key,
        account_id: 1,
        realm_name: "X",
        flags: 0,
        type: :pvp,
        note_text_id: 0
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerRealmInfo.write(packet, writer)

      binary = PacketWriter.to_binary(writer)

      # Skip to parse realm_name and then flags/type
      <<
        _addr::little-32,
        _port::little-16,
        _key::binary-size(16),
        _account_id::little-32,
        rest::binary
      >> = binary

      # Parse bit-packed wide string
      {_name, after_name} = parse_wide_string(rest)

      # flags (u32) + type (2 bits) + note_text_id (21 bits)
      <<_flags::little-32, type_bits::little-size(24)>> = after_name

      # PVP is type 1, in lowest 2 bits
      type_val = type_bits &&& 0x3
      assert type_val == 1
    end

    test "ip_to_uint32/1 converts IP correctly" do
      # 127.0.0.1 should be 0x7F000001 in big-endian
      assert ServerRealmInfo.ip_to_uint32("127.0.0.1") == 0x7F000001
      assert ServerRealmInfo.ip_to_uint32("192.168.1.1") == 0xC0A80101
      assert ServerRealmInfo.ip_to_uint32("0.0.0.0") == 0
    end

    test "realm_type_to_int/1 converts types correctly" do
      assert ServerRealmInfo.realm_type_to_int(:pve) == 0
      assert ServerRealmInfo.realm_type_to_int(:pvp) == 1
      assert ServerRealmInfo.realm_type_to_int(0) == 0
      assert ServerRealmInfo.realm_type_to_int(1) == 1
    end
  end

  # Helper to parse bit-packed wide string
  defp parse_wide_string(<<header::8, rest::binary>>) do
    extended = (header &&& 1) == 1

    if extended do
      <<second_byte::8, data::binary>> = rest
      length = ((second_byte <<< 7) ||| (header >>> 1)) &&& 0x7FFF
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = data
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    else
      length = header >>> 1
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = rest
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    end
  end
end
