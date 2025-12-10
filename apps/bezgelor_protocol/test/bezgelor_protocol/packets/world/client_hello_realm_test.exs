defmodule BezgelorProtocol.Packets.World.ClientHelloRealmTest do
  use ExUnit.Case, async: true

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

  # Helper to build a test packet
  defp build_packet(account_id, session_key, email) do
    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)

    <<
      account_id::little-32,
      session_key::binary-size(16),
      email_length::little-32,
      utf16_email::binary
    >>
  end
end
