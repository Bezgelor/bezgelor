defmodule BezgelorProtocol.PacketWriterTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketWriter

  describe "new/0" do
    test "creates empty writer" do
      writer = PacketWriter.new()
      assert is_struct(writer, PacketWriter)
    end
  end

  describe "write_byte/2" do
    test "writes single byte" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_byte(writer, 0xAB)
      assert PacketWriter.to_binary(writer) == <<0xAB>>
    end
  end

  describe "write_uint16/2" do
    test "writes little-endian uint16" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint16(writer, 0x1234)
      assert PacketWriter.to_binary(writer) == <<0x34, 0x12>>
    end
  end

  describe "write_uint32/2" do
    test "writes little-endian uint32" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint32(writer, 0x12345678)
      assert PacketWriter.to_binary(writer) == <<0x78, 0x56, 0x34, 0x12>>
    end
  end

  describe "write_uint64/2" do
    test "writes little-endian uint64" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint64(writer, 0x0123456789ABCDEF)
      assert PacketWriter.to_binary(writer) == <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>
    end
  end

  describe "write_bytes/2" do
    test "writes raw bytes" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bytes(writer, <<1, 2, 3>>)
      assert PacketWriter.to_binary(writer) == <<1, 2, 3>>
    end
  end

  describe "write_wide_string/2" do
    test "writes UTF-16LE string with length prefix" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_wide_string(writer, "hello")
      binary = PacketWriter.to_binary(writer)

      # Should have 4-byte length prefix (5) + 10 bytes of UTF-16LE
      assert byte_size(binary) == 14
      <<length::little-32, utf16::binary>> = binary
      assert length == 5
      assert :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8) == "hello"
    end
  end

  describe "write_bits/3" do
    test "writes specified number of bits" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bits(writer, 22, 5)  # 0b10110
      writer = PacketWriter.write_bits(writer, 6, 3)   # 0b110
      writer = PacketWriter.flush_bits(writer)
      # Combined: 0b110_10110 = 0xD6
      assert PacketWriter.to_binary(writer) == <<0xD6>>
    end
  end
end
