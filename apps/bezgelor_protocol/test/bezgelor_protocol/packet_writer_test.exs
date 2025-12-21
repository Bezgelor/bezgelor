defmodule BezgelorProtocol.PacketWriterTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketWriter

  describe "new/0" do
    test "creates empty writer" do
      writer = PacketWriter.new()
      assert is_struct(writer, PacketWriter)
    end
  end

  # ============================================================================
  # BIT-PACKED FUNCTIONS - These are the primary API for WildStar packets
  # ============================================================================

  describe "write_u8/2" do
    test "writes 8 bits into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_u8(writer, 0xAB)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<0xAB>>
    end
  end

  describe "write_u16/2" do
    test "writes 16 bits little-endian into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_u16(writer, 0x1234)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<0x34, 0x12>>
    end
  end

  describe "write_u32/2" do
    test "writes 32 bits little-endian into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_u32(writer, 0x12345678)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<0x78, 0x56, 0x34, 0x12>>
    end
  end

  describe "write_u64/2" do
    test "writes 64 bits little-endian into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_u64(writer, 0x0123456789ABCDEF)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>
    end
  end

  describe "write_i32/2" do
    test "writes positive signed 32-bit value" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_i32(writer, 12345)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<57, 48, 0, 0>>
    end

    test "writes negative signed 32-bit value (two's complement)" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_i32(writer, -1)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<0xFF, 0xFF, 0xFF, 0xFF>>
    end
  end

  describe "write_f32/2" do
    test "writes 32-bit float into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_f32(writer, 1.0)
      writer = PacketWriter.flush_bits(writer)
      # IEEE 754 representation of 1.0 in little-endian
      assert PacketWriter.to_binary(writer) == <<0, 0, 128, 63>>
    end
  end

  describe "write_bytes_bits/2" do
    test "writes raw bytes into bit stream" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bytes_bits(writer, <<1, 2, 3>>)
      writer = PacketWriter.flush_bits(writer)
      assert PacketWriter.to_binary(writer) == <<1, 2, 3>>
    end
  end

  describe "write_bits/3" do
    test "writes specified number of bits" do
      writer = PacketWriter.new()
      # 0b10110
      writer = PacketWriter.write_bits(writer, 22, 5)
      # 0b110
      writer = PacketWriter.write_bits(writer, 6, 3)
      writer = PacketWriter.flush_bits(writer)
      # Combined: 0b110_10110 = 0xD6
      assert PacketWriter.to_binary(writer) == <<0xD6>>
    end

    test "continuous bit stream across multiple writes" do
      # This test verifies the key WildStar protocol behavior:
      # All values are written as continuous bits without byte alignment
      writer =
        PacketWriter.new()
        # 2 bits
        |> PacketWriter.write_bits(0b11, 2)
        # 8 bits (should continue from bit 2)
        |> PacketWriter.write_u8(0xFF)
        # 3 bits
        |> PacketWriter.write_bits(0b101, 3)
        |> PacketWriter.flush_bits()

      # Total: 13 bits = 2 bytes (with 3 unused bits in last byte)
      # Byte 0: bits 0-1 = 0b11, bits 2-7 = 0b111111 (low 6 bits of 0xFF)
      #         = 0b11111111 = 0xFF
      # Byte 1: bits 0-1 = 0b11 (high 2 bits of 0xFF), bits 2-4 = 0b101
      #         = 0b00010111 = 0x17
      assert PacketWriter.to_binary(writer) == <<0xFF, 0x17>>
    end
  end

  describe "write_wide_string/2" do
    test "writes UTF-16LE string with bit-packed length prefix" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_wide_string(writer, "Hi")
      writer = PacketWriter.flush_bits(writer)
      binary = PacketWriter.to_binary(writer)

      # Short string (length <= 127): 1 bit extended (0) + 7 bits length + UTF-16LE
      # Length = 2, extended = 0, so prefix byte = 0b0000010_0 = 0x04
      # But wait, it's bit-packed so: bit 0 = extended (0), bits 1-7 = length (2)
      # = 0b0000010_0 = 0x04
      # UTF-16LE "Hi" = <<0x48, 0x00, 0x69, 0x00>>
      assert binary == <<0x04, 0x48, 0x00, 0x69, 0x00>>
    end
  end

  # ============================================================================
  # BYTE-ALIGNED FUNCTIONS - These flush the bit stream first
  # ============================================================================

  describe "write_byte_flush/2" do
    test "flushes bits then writes byte-aligned" do
      writer = PacketWriter.new()
      # Write 3 bits, then flush with byte write
      writer = PacketWriter.write_bits(writer, 0b101, 3)
      writer = PacketWriter.write_byte_flush(writer, 0xAB)
      assert PacketWriter.to_binary(writer) == <<0x05, 0xAB>>
    end
  end

  describe "write_uint32_flush/2" do
    test "flushes bits then writes byte-aligned uint32" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint32_flush(writer, 0x12345678)
      assert PacketWriter.to_binary(writer) == <<0x78, 0x56, 0x34, 0x12>>
    end
  end

  describe "write_bytes_flush/2" do
    test "flushes bits then writes raw bytes" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bits(writer, 0b11, 2)
      writer = PacketWriter.write_bytes_flush(writer, <<0xAA, 0xBB>>)
      # First byte: 0b00000011 = 0x03 (flushed bits)
      # Then raw bytes
      assert PacketWriter.to_binary(writer) == <<0x03, 0xAA, 0xBB>>
    end
  end

  # ============================================================================
  # PACKED FLOAT FUNCTIONS
  # ============================================================================

  describe "write_packed_float/2" do
    test "writes half-precision float" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_packed_float(writer, 1.0)
      writer = PacketWriter.flush_bits(writer)
      # Half-precision 1.0 = 0x3C00
      assert PacketWriter.to_binary(writer) == <<0x00, 0x3C>>
    end
  end

  describe "write_packed_vector3/2" do
    test "writes three half-precision floats" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_packed_vector3(writer, {1.0, 0.0, -1.0})
      writer = PacketWriter.flush_bits(writer)
      # 6 bytes total (3 x 16-bit)
      assert byte_size(PacketWriter.to_binary(writer)) == 6
    end
  end

  describe "write_vector3/2" do
    test "writes three 32-bit floats" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_vector3(writer, {1.0, 2.0, 3.0})
      writer = PacketWriter.flush_bits(writer)
      # 12 bytes total (3 x 32-bit)
      assert byte_size(PacketWriter.to_binary(writer)) == 12
    end
  end
end
