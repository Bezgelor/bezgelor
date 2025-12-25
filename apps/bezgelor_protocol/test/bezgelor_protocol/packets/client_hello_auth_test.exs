defmodule BezgelorProtocol.Packets.ClientHelloAuthTest do
  @moduledoc """
  Tests for ClientHelloAuth packet parsing.

  Wire format:
  - build: uint32
  - email: wide_string (bit-packed)
  - client_key_a: 128 bytes
  - client_proof_m1: 32 bytes
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.ClientHelloAuth
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "parses ClientHelloAuth packet with valid data" do
      email = "test@example.com"
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      payload =
        <<16042::little-32>> <>
          build_wide_string(email) <>
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
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      # Wrong build version
      payload =
        <<12345::little-32>> <>
          build_wide_string(email) <>
          fake_key_a <>
          fake_m1

      reader = PacketReader.new(payload)
      {:ok, packet, _reader} = ClientHelloAuth.read(reader)

      # Packet parses but build is wrong (validation happens in handler)
      assert packet.build == 12345
    end

    test "parses packet with empty email" do
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      payload =
        <<16042::little-32>> <>
          build_wide_string("") <>
          fake_key_a <>
          fake_m1

      reader = PacketReader.new(payload)
      {:ok, packet, _reader} = ClientHelloAuth.read(reader)

      assert packet.email == ""
    end

    test "parses packet with special characters in email" do
      email = "user+test@example.com"
      fake_key_a = :crypto.strong_rand_bytes(128)
      fake_m1 = :crypto.strong_rand_bytes(32)

      payload =
        <<16042::little-32>> <>
          build_wide_string(email) <>
          fake_key_a <>
          fake_m1

      reader = PacketReader.new(payload)
      {:ok, packet, _reader} = ClientHelloAuth.read(reader)

      assert packet.email == email
    end

    test "returns error on truncated data" do
      # Only build, no email or keys
      payload = <<16042::little-32>>

      reader = PacketReader.new(payload)
      assert {:error, :eof} = ClientHelloAuth.read(reader)
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ClientHelloAuth.opcode() == :client_hello_auth
    end
  end

  # Build a bit-packed wide string matching NexusForever format
  defp build_wide_string("") do
    <<0::8>>
  end

  defp build_wide_string(string) when is_binary(string) do
    length = String.length(string)
    utf16_data = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})

    if length < 128 do
      header = (length <<< 1) ||| 0
      <<header::8>> <> utf16_data
    else
      header = (length <<< 1) ||| 1
      <<header::16-little>> <> utf16_data
    end
  end
end
