defmodule BezgelorProtocol.Packets.Realm.ClientHelloAuthTest do
  @moduledoc """
  Tests for ClientHelloAuth packet parsing.

  The packet includes hardware info that must be skipped during parsing.
  """
  use ExUnit.Case, async: true

  import Bitwise

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

    test "parses datacenter_id correctly" do
      payload = build_packet(16042, 0x1588, "test@test.com", random_uuid(), random_uuid(),
        datacenter_id: 42
      )
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientHelloAuth.read(reader)
      assert packet.realm_datacenter_id == 42
    end
  end

  # Helper to build a complete test packet including hardware info
  defp build_packet(build, crypt_key, email, uuid_1, game_token, opts \\ []) do
    inet_address = Keyword.get(opts, :inet_address, 0)
    language = Keyword.get(opts, :language, 0)
    game_mode = Keyword.get(opts, :game_mode, 0)
    unused = Keyword.get(opts, :unused, 0)
    datacenter_id = Keyword.get(opts, :datacenter_id, 0)

    # Email uses read_wide_string_fixed: uint16 length (including null terminator)
    # + length*2 bytes UTF-16LE (last 2 bytes are null terminator which gets stripped)
    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    # Length includes the null terminator character
    email_length = String.length(email) + 1

    # Build the base packet
    base =
      <<
        build::little-32,
        crypt_key::little-64,
        # read_wide_string_fixed: uint16 length prefix (includes null terminator)
        email_length::little-16,
        # UTF-16LE data + null terminator (2 bytes)
        utf16_email::binary, 0::16,
        uuid_1::binary-size(16),
        game_token::binary-size(16),
        inet_address::little-32,
        language::little-32,
        game_mode::little-32,
        unused::little-32
      >>

    # Add hardware info that skip_hardware_info expects
    hardware_info = build_hardware_info()

    # Add final datacenter_id
    base <> hardware_info <> <<datacenter_id::little-32>>
  end

  # Build hardware info matching what skip_hardware_info/skip_cpu_info/skip_gpu_info expect
  defp build_hardware_info do
    # CPU info: 3 wide strings (bit-packed) + 5 uint32s
    cpu_info =
      build_wide_string("Intel") <>
      build_wide_string("Core i7") <>
      build_wide_string("8th Gen") <>
      <<0::little-32, 0::little-32, 0::little-32, 0::little-32, 0::little-32>>

    # Memory: 1 uint32
    memory = <<16384::little-32>>

    # GPU info: 1 wide string (bit-packed) + 5 uint32s
    gpu_info =
      build_wide_string("NVIDIA GTX") <>
      <<0::little-32, 0::little-32, 0::little-32, 0::little-32, 0::little-32>>

    # OS info: 4 uint32s
    os_info = <<0::little-32, 0::little-32, 0::little-32, 0::little-32>>

    cpu_info <> memory <> gpu_info <> os_info
  end

  # Build a bit-packed wide string for hardware info fields
  # Format: 1 bit extended + 7/15 bits length + UTF-16LE data
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

  defp random_uuid, do: :crypto.strong_rand_bytes(16)
end
