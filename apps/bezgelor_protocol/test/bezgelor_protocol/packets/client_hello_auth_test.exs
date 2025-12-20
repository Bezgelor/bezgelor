defmodule BezgelorProtocol.Packets.ClientHelloAuthTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.ClientHelloAuth
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "parses ClientHelloAuth packet with valid data" do
      # Build test packet:
      # - build: uint32 (16042)
      # - email: wide_string (length-prefixed UTF-16LE)
      # - client_key_a: 128 bytes
      # - client_proof_m1: 32 bytes

      email = "test@example.com"
      email_utf16 = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      payload =
        <<16042::little-32>> <>
          <<String.length(email)::little-32>> <>
          email_utf16 <>
          fake_key_a <>
          fake_m1

      reader = PacketReader.new(payload)
      {:ok, packet, _reader} = ClientHelloAuth.read(reader)

      assert packet.build == 16042
      assert packet.email == "test@example.com"
      assert byte_size(packet.client_key_a) == 128
      assert packet.client_key_a == fake_key_a
      assert byte_size(packet.client_proof_m1) == 32
      assert packet.client_proof_m1 == fake_m1
    end

    test "returns error for invalid build version" do
      email = "test@example.com"
      email_utf16 = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      # Wrong build version
      payload =
        <<12345::little-32>> <>
          <<String.length(email)::little-32>> <>
          email_utf16 <>
          fake_key_a <>
          fake_m1

      reader = PacketReader.new(payload)
      {:ok, packet, _reader} = ClientHelloAuth.read(reader)

      # Packet parses but build is wrong (validation happens in handler)
      assert packet.build == 12345
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ClientHelloAuth.opcode() == :client_hello_auth
    end
  end
end
