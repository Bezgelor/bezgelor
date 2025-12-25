defmodule BezgelorProtocol.Packets.World.ClientHelloRealmTest do
  @moduledoc """
  Tests for ClientHelloRealm packet parsing.

  Wire format:
  - account_id:  uint32
  - session_key: 16 bytes
  - unused:      uint64 (always 0)
  - email:       wide_string (bit-packed)
  - always3:     uint32 (always 3)
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.World.ClientHelloRealm
  alias BezgelorProtocol.PacketReader

  describe "opcode/0" do
    test "returns the correct opcode" do
      assert ClientHelloRealm.opcode() == :client_hello_realm
    end
  end

  describe "read/1" do
    test "parses a valid ClientHelloRealm packet" do
      account_id = 12345
      session_key = :crypto.strong_rand_bytes(16)
      email = "test@example.com"

      payload = build_packet(account_id, session_key, email)
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloRealm.read(reader)
      assert packet.account_id == account_id
      assert packet.session_key == session_key
      assert packet.email == email
      assert packet.unused == 0
      assert packet.always3 == 3
    end

    test "preserves session key bytes exactly" do
      session_key = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      payload = build_packet(999, session_key, "user@test.com")
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloRealm.read(reader)
      assert packet.session_key == session_key
    end

    test "parses email with special characters" do
      email = "user+world@test.com"
      payload = build_packet(1, :crypto.strong_rand_bytes(16), email)
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloRealm.read(reader)
      assert packet.email == email
    end

    test "parses high account_id" do
      account_id = 4_294_967_295
      payload = build_packet(account_id, :crypto.strong_rand_bytes(16), "test@test.com")
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloRealm.read(reader)
      assert packet.account_id == account_id
    end

    test "returns error on truncated data" do
      # Only account_id, partial session key
      payload = <<12345::little-32, 1, 2, 3, 4, 5>>
      reader = PacketReader.new(payload)

      assert {:error, :eof} = ClientHelloRealm.read(reader)
    end
  end

  # Build a complete test packet matching wire format
  defp build_packet(account_id, session_key, email) do
    email_data = build_wide_string(email)

    <<
      account_id::little-32,
      session_key::binary-size(16),
      # unused: uint64 always 0
      0::little-64,
      email_data::binary,
      # always3: uint32 always 3
      3::little-32
    >>
  end

  # Build a bit-packed wide string matching NexusForever format:
  # - 1 bit: extended flag (0 for length < 128, 1 for length >= 128)
  # - 7 or 15 bits: length in characters
  # - length * 2 bytes: UTF-16LE string data
  defp build_wide_string("") do
    <<0::8>>
  end

  defp build_wide_string(string) when is_binary(string) do
    length = String.length(string)
    utf16_data = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})

    if length < 128 do
      # Short string: extended=0 (bit 0), length in bits 1-7
      header = (length <<< 1) ||| 0
      <<header::8>> <> utf16_data
    else
      # Long string: extended=1 (bit 0), length in bits 1-15
      header = (length <<< 1) ||| 1
      <<header::16-little>> <> utf16_data
    end
  end
end
