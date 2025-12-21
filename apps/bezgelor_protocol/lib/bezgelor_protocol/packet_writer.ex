defmodule BezgelorProtocol.PacketWriter do
  @moduledoc """
  Bit-level packet writer for WildStar protocol.

  ## Overview

  WildStar packets use **continuous bit-packed serialization**. All data is written
  into a single bit stream without byte alignment between fields. This matches
  NexusForever's GamePacketWriter behavior.

  ## IMPORTANT: Bit-Packed vs Byte-Aligned Functions

  This module provides two types of write functions:

  ### Bit-Packed Functions (USE THESE IN PACKETS)

  These write directly into the continuous bit stream:

  - `write_u8/2`, `write_u16/2`, `write_u32/2`, `write_u64/2` - unsigned integers
  - `write_i32/2` - signed 32-bit integer
  - `write_f32/2` - 32-bit float
  - `write_bits/3` - arbitrary bit count

  ### Byte-Aligned Functions (RARELY NEEDED)

  These flush any pending bits first, breaking the bit stream. Only use these
  at packet boundaries or for non-WildStar protocols:

  - `write_byte_flush/2`, `write_uint16_flush/2`, `write_uint32_flush/2`, etc.

  ## Example

      writer = PacketWriter.new()
      |> PacketWriter.write_u32(12345)      # 32 bits into stream
      |> PacketWriter.write_bits(3, 5)      # 5 bits into stream
      |> PacketWriter.write_u8(255)         # 8 bits into stream
      |> PacketWriter.flush_bits()

      binary = PacketWriter.to_binary(writer)
  """

  import Bitwise

  defstruct [:buffer, :bit_pos, :bit_value]

  @type t :: %__MODULE__{
          buffer: iodata(),
          bit_pos: non_neg_integer(),
          bit_value: non_neg_integer()
        }

  @doc "Create a new empty writer."
  @spec new() :: t()
  def new do
    %__MODULE__{
      buffer: [],
      bit_pos: 0,
      bit_value: 0
    }
  end

  @doc "Convert writer contents to binary."
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{buffer: buffer}) do
    IO.iodata_to_binary(buffer)
  end

  # ============================================================================
  # BIT-PACKED FUNCTIONS - Use these in packet serialization
  # ============================================================================

  @doc """
  Write an unsigned 8-bit integer into the bit stream.

  This is the preferred way to write bytes in WildStar packets.
  """
  @spec write_u8(t(), non_neg_integer()) :: t()
  def write_u8(%__MODULE__{} = writer, value) when value >= 0 do
    write_bits(writer, value, 8)
  end

  @doc """
  Write an unsigned 16-bit integer into the bit stream.
  """
  @spec write_u16(t(), non_neg_integer()) :: t()
  def write_u16(%__MODULE__{} = writer, value) when value >= 0 do
    write_bits(writer, value, 16)
  end

  @doc """
  Write an unsigned 32-bit integer into the bit stream.

  This is the preferred way to write uint32 values in WildStar packets.
  """
  @spec write_u32(t(), non_neg_integer()) :: t()
  def write_u32(%__MODULE__{} = writer, value) when value >= 0 do
    write_bits(writer, value, 32)
  end

  @doc """
  Write an unsigned 64-bit integer into the bit stream.

  This is the preferred way to write uint64 values in WildStar packets.
  """
  @spec write_u64(t(), non_neg_integer()) :: t()
  def write_u64(%__MODULE__{} = writer, value) when value >= 0 do
    write_bits(writer, value, 64)
  end

  @doc """
  Write a signed 32-bit integer into the bit stream.

  Negative values are written using two's complement representation.
  """
  @spec write_i32(t(), integer()) :: t()
  def write_i32(%__MODULE__{} = writer, value) do
    # Convert to unsigned using two's complement for negative values
    unsigned = :erlang.band(value, 0xFFFFFFFF)
    write_bits(writer, unsigned, 32)
  end

  @doc """
  Write a 32-bit float into the bit stream.

  The float is converted to its IEEE 754 binary representation and
  written as 32 bits. This is the preferred way to write floats in
  WildStar packets.
  """
  @spec write_f32(t(), float()) :: t()
  def write_f32(%__MODULE__{} = writer, value) do
    <<int_value::little-unsigned-32>> = <<value::little-float-32>>
    write_bits(writer, int_value, 32)
  end

  @doc "Write specified number of bits into the bit stream."
  @spec write_bits(t(), non_neg_integer(), pos_integer()) :: t()
  def write_bits(%__MODULE__{} = writer, value, count) when count > 0 do
    write_bits_acc(writer, value, count)
  end

  @doc """
  Write raw bytes into the continuous bit stream (not byte-aligned).

  Each byte is written as 8 bits into the bit stream, maintaining
  the current bit position. Use this for bit-packed protocols.
  """
  @spec write_bytes_bits(t(), binary()) :: t()
  def write_bytes_bits(%__MODULE__{} = writer, bytes) when is_binary(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.reduce(writer, fn byte, w ->
      write_bits(w, byte, 8)
    end)
  end

  @doc """
  Write a packed float (half-precision, 16-bit) into the bit stream.

  This matches NexusForever's GamePacketWriter.WritePackedFloat() - it converts
  a 32-bit float into a 16-bit representation for more efficient transmission.
  """
  @spec write_packed_float(t(), float()) :: t()
  def write_packed_float(%__MODULE__{} = writer, value) do
    packed = pack_float(value)
    write_bits(writer, packed, 16)
  end

  @doc """
  Write a packed Vector3 (three half-precision floats) into the bit stream.

  Each component is packed as a 16-bit float.
  """
  @spec write_packed_vector3(t(), {float(), float(), float()}) :: t()
  def write_packed_vector3(%__MODULE__{} = writer, {x, y, z}) do
    writer
    |> write_packed_float(x)
    |> write_packed_float(y)
    |> write_packed_float(z)
  end

  @doc """
  Write a full Vector3 (three 32-bit floats) into the bit stream.

  Each component is written as a 32-bit IEEE 754 float.
  """
  @spec write_vector3(t(), {float(), float(), float()}) :: t()
  def write_vector3(%__MODULE__{} = writer, {x, y, z}) do
    writer
    |> write_f32(x)
    |> write_f32(y)
    |> write_f32(z)
  end

  @doc """
  Write a UTF-16LE string with bit-packed length prefix.

  This matches NexusForever's GamePacketWriter.WriteStringWide():
  - 1 bit: extended flag (1 if length > 127)
  - 7 or 15 bits: length in characters
  - UTF-16LE encoded string data (written as bits, not byte-aligned)
  """
  @spec write_wide_string(t(), String.t()) :: t()
  def write_wide_string(%__MODULE__{} = writer, string) when is_binary(string) do
    utf16 = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})
    # Length in characters (UTF-16 bytes / 2)
    length = div(byte_size(utf16), 2)
    extended = length > 0x7F

    writer
    |> write_bits(if(extended, do: 1, else: 0), 1)
    |> write_bits(length, if(extended, do: 15, else: 7))
    |> write_bytes_bits(utf16)
  end

  # ============================================================================
  # BYTE-ALIGNED FUNCTIONS - These flush the bit stream first!
  # Only use at packet boundaries or for non-WildStar protocols.
  # ============================================================================

  @doc """
  Write a single byte (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_byte_flush(t(), non_neg_integer()) :: t()
  def write_byte_flush(%__MODULE__{} = writer, byte) when byte >= 0 and byte <= 255 do
    writer
    |> flush_bits()
    |> append_bytes(<<byte>>)
  end

  @doc """
  Write a little-endian uint16 (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_uint16_flush(t(), non_neg_integer()) :: t()
  def write_uint16_flush(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-16>>)
  end

  @doc """
  Write a little-endian uint32 (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_uint32_flush(t(), non_neg_integer()) :: t()
  def write_uint32_flush(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-32>>)
  end

  @doc """
  Write a little-endian signed int32 (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_int32_flush(t(), integer()) :: t()
  def write_int32_flush(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-signed-32>>)
  end

  @doc """
  Write a little-endian uint64 (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_uint64_flush(t(), non_neg_integer()) :: t()
  def write_uint64_flush(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-64>>)
  end

  @doc """
  Write a little-endian float32 (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_float32_flush(t(), float()) :: t()
  def write_float32_flush(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-float-32>>)
  end

  @doc """
  Write raw bytes (FLUSHES bit stream first).

  WARNING: This breaks the continuous bit stream. Only use at packet
  boundaries or for protocols that require byte alignment.
  """
  @spec write_bytes_flush(t(), binary()) :: t()
  def write_bytes_flush(%__MODULE__{} = writer, bytes) when is_binary(bytes) do
    writer
    |> flush_bits()
    |> append_bytes(bytes)
  end

  @doc "Write a UTF-16LE string with uint32 length prefix (legacy format, byte-aligned)."
  @spec write_wide_string_legacy(t(), String.t()) :: t()
  def write_wide_string_legacy(%__MODULE__{} = writer, string) when is_binary(string) do
    utf16 = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})
    length = String.length(string)

    writer
    |> write_uint32_flush(length)
    |> write_bytes_flush(utf16)
  end

  # ============================================================================
  # DEPRECATED ALIASES - These will be removed in a future version
  # ============================================================================

  @doc false
  @deprecated "Use write_byte_flush/2 or write_u8/2 instead"
  def write_byte(writer, value), do: write_byte_flush(writer, value)

  @doc false
  @deprecated "Use write_uint16_flush/2 or write_u16/2 instead"
  def write_uint16(writer, value), do: write_uint16_flush(writer, value)

  @doc false
  @deprecated "Use write_uint32_flush/2 or write_u32/2 instead"
  def write_uint32(writer, value), do: write_uint32_flush(writer, value)

  @doc false
  @deprecated "Use write_int32_flush/2 or write_i32/2 instead"
  def write_int32(writer, value), do: write_int32_flush(writer, value)

  @doc false
  @deprecated "Use write_uint64_flush/2 or write_u64/2 instead"
  def write_uint64(writer, value), do: write_uint64_flush(writer, value)

  @doc false
  @deprecated "Use write_float32_flush/2 or write_f32/2 instead"
  def write_float32(writer, value), do: write_float32_flush(writer, value)

  @doc false
  @deprecated "Use write_bytes_flush/2 or write_bytes_bits/2 instead"
  def write_bytes(writer, bytes), do: write_bytes_flush(writer, bytes)

  # Keep these as aliases for backwards compatibility (they were already bit-packed)
  @doc false
  def write_float32_bits(writer, value), do: write_f32(writer, value)
  @doc false
  def write_uint64_bits(writer, value), do: write_u64(writer, value)
  @doc false
  def write_uint32_bits(writer, value), do: write_u32(writer, value)

  # ============================================================================
  # INTERNAL FUNCTIONS
  # ============================================================================

  @doc "Flush any remaining bits to the buffer."
  @spec flush_bits(t()) :: t()
  def flush_bits(%__MODULE__{bit_pos: 0} = writer), do: writer

  def flush_bits(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer) when bit_pos > 0 do
    writer
    |> append_bytes(<<bit_value>>)
    |> Map.put(:bit_pos, 0)
    |> Map.put(:bit_value, 0)
  end

  # Pack a 32-bit float into 16-bit half-precision format
  # Algorithm from NexusForever's GamePacketWriter.WritePackedFloat
  defp pack_float(value) do
    import Bitwise
    <<v1::unsigned-32>> = <<value::float-32>>
    v2 = band(v1, 0x7FFFFFFF)
    v3 = band(bsr(v1, 16), 0x8000)

    cond do
      v2 < 0x33800000 ->
        # Very small values map to zero
        v3

      v2 <= 0x387FEFFF ->
        # Denormalized half-float
        mantissa = bor(band(v1, 0x7FFFFF), 0x800000)
        exponent = bsr(band(v1, 0x7FFFFFFF), 23)
        shift = 113 - exponent
        bor(v3, bsr(bsr(mantissa, shift) + 4096, 13))

      v2 > 0x47FFEFFF ->
        # Overflow - clamp to max half-float
        bor(v3, 0x43FF)

      true ->
        # Normal conversion
        bor(v3, bsr(v2 - 0x37FFF000, 13))
    end
  end

  defp append_bytes(%__MODULE__{buffer: buffer} = writer, bytes) do
    %{writer | buffer: [buffer, bytes]}
  end

  defp write_bits_acc(writer, _value, 0), do: writer

  defp write_bits_acc(
         %__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer,
         value,
         remaining
       ) do
    bits_available = 8 - bit_pos
    bits_to_write = min(remaining, bits_available)
    mask = (1 <<< bits_to_write) - 1
    bits = band(value, mask)

    new_bit_value = bor(bit_value, bsl(bits, bit_pos))
    new_bit_pos = bit_pos + bits_to_write

    writer =
      if new_bit_pos == 8 do
        writer
        |> append_bytes(<<new_bit_value>>)
        |> Map.put(:bit_pos, 0)
        |> Map.put(:bit_value, 0)
      else
        %{writer | bit_pos: new_bit_pos, bit_value: new_bit_value}
      end

    write_bits_acc(writer, bsr(value, bits_to_write), remaining - bits_to_write)
  end
end
