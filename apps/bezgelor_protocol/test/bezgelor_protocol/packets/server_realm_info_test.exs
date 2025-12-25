defmodule BezgelorProtocol.Packets.ServerRealmInfoTest do
  @moduledoc """
  Tests for ServerRealmInfo packet serialization.

  Wire format:
  - account_id:    uint32
  - realm_id:      uint32
  - realm_name:    wide_string (bit-packed)
  - realm_address: null-terminated ASCII string
  - session_key:   16 bytes
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.ServerRealmInfo
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes packet with realm information" do
      session_key = :crypto.strong_rand_bytes(16)

      packet = %ServerRealmInfo{
        account_id: 12345,
        realm_id: 1,
        realm_name: "Nexus",
        realm_address: "127.0.0.1:24000",
        session_key: session_key
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerRealmInfo.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse back - bit-packed wide string format
      <<
        account_id::little-32,
        realm_id::little-32,
        rest::binary
      >> = binary

      assert account_id == 12345
      assert realm_id == 1

      # Parse bit-packed wide string for realm_name
      {name, after_name} = parse_wide_string(rest)
      assert name == "Nexus"

      # Address is null-terminated string followed by session_key
      {address, <<key::binary-size(16)>>} = split_null_string(after_name)
      assert address == "127.0.0.1:24000"
      assert key == session_key
    end

    test "returns correct opcode" do
      assert ServerRealmInfo.opcode() == :server_realm_info
    end
  end

  # Parse bit-packed wide string from binary
  # Format: 1 bit extended + 7/15 bits length + UTF-16LE data
  defp parse_wide_string(<<header::8, rest::binary>>) do
    extended = (header &&& 1) == 1

    if extended do
      # Long string: read second byte for full 15-bit length
      <<second_byte::8, data::binary>> = rest
      length = ((second_byte <<< 7) ||| (header >>> 1)) &&& 0x7FFF
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = data
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    else
      # Short string: 7-bit length
      length = header >>> 1
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = rest
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    end
  end

  defp split_null_string(binary) do
    case :binary.split(binary, <<0>>) do
      [str, rest] -> {str, rest}
      [str] -> {str, <<>>}
    end
  end
end
