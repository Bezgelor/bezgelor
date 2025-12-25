defmodule BezgelorProtocol.PacketReaderTest do
  @moduledoc """
  Tests for PacketReader binary parsing utilities.
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.PacketReader

  describe "new/1" do
    test "creates reader from binary" do
      reader = PacketReader.new(<<1, 2, 3, 4>>)
      assert is_struct(reader, PacketReader)
    end
  end

  describe "read_byte/1" do
    test "reads single byte" do
      reader = PacketReader.new(<<0xAB, 0xCD>>)
      assert {:ok, 0xAB, reader} = PacketReader.read_byte(reader)
      assert {:ok, 0xCD, _reader} = PacketReader.read_byte(reader)
    end
  end

  describe "read_uint16/1" do
    test "reads little-endian uint16" do
      reader = PacketReader.new(<<0x34, 0x12>>)
      assert {:ok, 0x1234, _reader} = PacketReader.read_uint16(reader)
    end
  end

  describe "read_uint32/1" do
    test "reads little-endian uint32" do
      reader = PacketReader.new(<<0x78, 0x56, 0x34, 0x12>>)
      assert {:ok, 0x12345678, _reader} = PacketReader.read_uint32(reader)
    end
  end

  describe "read_uint64/1" do
    test "reads little-endian uint64" do
      reader = PacketReader.new(<<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>)
      assert {:ok, 0x0123456789ABCDEF, _reader} = PacketReader.read_uint64(reader)
    end
  end

  describe "read_bytes/2" do
    test "reads specified number of bytes" do
      reader = PacketReader.new(<<1, 2, 3, 4, 5>>)
      assert {:ok, <<1, 2, 3>>, reader} = PacketReader.read_bytes(reader, 3)
      assert {:ok, <<4, 5>>, _reader} = PacketReader.read_bytes(reader, 2)
    end
  end

  describe "read_string/1" do
    test "reads null-terminated string" do
      reader = PacketReader.new(<<"hello", 0, "world">>)
      assert {:ok, "hello", _reader} = PacketReader.read_string(reader)
    end
  end

  describe "read_wide_string/1" do
    test "reads bit-packed UTF-16LE string" do
      # Bit-packed format: 1 bit extended + 7/15 bits length + UTF-16LE data
      # "hello" = 5 chars, extended=0, header = (5 << 1) | 0 = 10
      data = build_wide_string("hello")
      reader = PacketReader.new(data)
      assert {:ok, "hello", _reader} = PacketReader.read_wide_string(reader)
    end

    test "reads empty string" do
      data = build_wide_string("")
      reader = PacketReader.new(data)
      assert {:ok, "", _reader} = PacketReader.read_wide_string(reader)
    end

    test "reads string with special characters" do
      data = build_wide_string("Test123!")
      reader = PacketReader.new(data)
      assert {:ok, "Test123!", _reader} = PacketReader.read_wide_string(reader)
    end
  end

  describe "read_bits/2" do
    test "reads specified number of bits" do
      # Binary: 0b11010110 = 0xD6
      reader = PacketReader.new(<<0xD6>>)
      # Read 5 bits: should get 0b10110 = 22
      assert {:ok, 22, reader} = PacketReader.read_bits(reader, 5)
      # Read 3 bits: should get 0b110 = 6
      assert {:ok, 6, _reader} = PacketReader.read_bits(reader, 3)
    end
  end

  # Build a bit-packed wide string matching NexusForever format:
  # - 1 bit: extended flag (0 for length < 128, 1 for length >= 128)
  # - 7 or 15 bits: length in characters
  # - length * 2 bytes: UTF-16LE string data
  defp build_wide_string("") do
    # Empty string: extended=0, length=0, no data
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
