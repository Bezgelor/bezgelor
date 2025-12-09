defmodule BezgelorProtocol.PacketReaderTest do
  use ExUnit.Case, async: true

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
    test "reads UTF-16LE string with length prefix" do
      # Length = 5, then "hello" in UTF-16LE
      data = <<5, 0, 0, 0>> <> :unicode.characters_to_binary("hello", :utf8, {:utf16, :little})
      reader = PacketReader.new(data)
      assert {:ok, "hello", _reader} = PacketReader.read_wide_string(reader)
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
end
