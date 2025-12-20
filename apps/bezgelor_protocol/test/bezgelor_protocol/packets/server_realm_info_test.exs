defmodule BezgelorProtocol.Packets.ServerRealmInfoTest do
  use ExUnit.Case, async: true

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

      # Parse it back to verify structure
      <<
        account_id::little-32,
        realm_id::little-32,
        name_len::little-32,
        rest::binary
      >> = binary

      assert account_id == 12345
      assert realm_id == 1
      # "Nexus" length
      assert name_len == 5

      # Skip UTF-16LE name (5 * 2 = 10 bytes)
      <<_name::binary-size(10), after_name::binary>> = rest

      # Address is null-terminated string
      {address, <<key::binary-size(16)>>} = split_null_string(after_name)
      assert address == "127.0.0.1:24000"
      assert key == session_key
    end

    test "returns correct opcode" do
      assert ServerRealmInfo.opcode() == :server_realm_info
    end
  end

  defp split_null_string(binary) do
    case :binary.split(binary, <<0>>) do
      [str, rest] -> {str, rest}
      [str] -> {str, <<>>}
    end
  end
end
