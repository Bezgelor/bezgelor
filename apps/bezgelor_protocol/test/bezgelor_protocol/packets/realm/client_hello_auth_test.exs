defmodule BezgelorProtocol.Packets.Realm.ClientHelloAuthTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.Realm.ClientHelloAuth
  alias BezgelorProtocol.PacketReader

  describe "opcode/0" do
    test "returns the correct opcode" do
      assert ClientHelloAuth.opcode() == :client_hello_auth_realm
    end
  end

  describe "read/1" do
    test "parses a valid ClientHelloAuth packet" do
      email = "test@example.com"
      uuid_1 = :crypto.strong_rand_bytes(16)
      game_token = :crypto.strong_rand_bytes(16)

      payload = build_packet(16042, 0x1588, email, uuid_1, game_token)
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloAuth.read(reader)
      assert packet.build == 16042
      assert packet.crypt_key_integer == 0x1588
      assert packet.email == email
      assert packet.uuid_1 == uuid_1
      assert packet.game_token == game_token
    end

    test "parses packet with different build version" do
      payload = build_packet(99999, 0x1588, "user@test.com", random_uuid(), random_uuid())
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloAuth.read(reader)
      assert packet.build == 99999
    end

    test "parses email with special characters" do
      email = "test+special@example.com"
      payload = build_packet(16042, 0x1588, email, random_uuid(), random_uuid())
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloAuth.read(reader)
      assert packet.email == email
    end

    test "preserves game token bytes exactly" do
      game_token = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      payload = build_packet(16042, 0x1588, "test@test.com", random_uuid(), game_token)
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloAuth.read(reader)
      assert packet.game_token == game_token
    end

    test "returns error on truncated data" do
      # Only build and partial crypt_key
      payload = <<16042::little-32, 0x1588::little-32>>
      reader = PacketReader.new(payload)

      assert {:error, :eof} = ClientHelloAuth.read(reader)
    end
  end

  # Helper to build a test packet
  defp build_packet(build, crypt_key, email, uuid_1, game_token, opts \\ []) do
    inet_address = Keyword.get(opts, :inet_address, 0)
    language = Keyword.get(opts, :language, 0)
    game_mode = Keyword.get(opts, :game_mode, 0)
    unused = Keyword.get(opts, :unused, 0)
    datacenter_id = Keyword.get(opts, :datacenter_id, 0)

    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)

    <<
      build::little-32,
      crypt_key::little-64,
      email_length::little-32,
      utf16_email::binary,
      uuid_1::binary-size(16),
      game_token::binary-size(16),
      inet_address::little-32,
      language::little-32,
      game_mode::little-32,
      unused::little-32,
      datacenter_id::little-32
    >>
  end

  defp random_uuid, do: :crypto.strong_rand_bytes(16)
end
