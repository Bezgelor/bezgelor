defmodule BezgelorProtocol.PacketWriter do
  @moduledoc """
  Bit-level packet writer for WildStar protocol.

  ## Overview

  WildStar packets use bit-packed serialization. This writer supports both
  byte-aligned and bit-level writes, building up binary data.

  ## Example

      writer = PacketWriter.new()
      |> PacketWriter.write_uint32(12345)
      |> PacketWriter.write_bits(3, 5)  # 3 in 5 bits
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

  @doc "Write a single byte."
  @spec write_byte(t(), non_neg_integer()) :: t()
  def write_byte(%__MODULE__{} = writer, byte) when byte >= 0 and byte <= 255 do
    writer
    |> flush_bits()
    |> append_bytes(<<byte>>)
  end

  @doc "Write a little-endian uint16."
  @spec write_uint16(t(), non_neg_integer()) :: t()
  def write_uint16(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-16>>)
  end

  @doc "Write a little-endian uint32."
  @spec write_uint32(t(), non_neg_integer()) :: t()
  def write_uint32(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-32>>)
  end

  @doc "Write a little-endian signed int32."
  @spec write_int32(t(), integer()) :: t()
  def write_int32(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-signed-32>>)
  end

  @doc "Write a little-endian uint64."
  @spec write_uint64(t(), non_neg_integer()) :: t()
  def write_uint64(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-64>>)
  end

  @doc "Write a little-endian float32."
  @spec write_float32(t(), float()) :: t()
  def write_float32(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-float-32>>)
  end

  @doc "Write raw bytes (byte-aligned)."
  @spec write_bytes(t(), binary()) :: t()
  def write_bytes(%__MODULE__{} = writer, bytes) when is_binary(bytes) do
    writer
    |> flush_bits()
    |> append_bytes(bytes)
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
  Write a float32 into the continuous bit stream (not byte-aligned).

  The float is converted to its IEEE 754 binary representation and
  written as 32 bits into the bit stream.
  """
  @spec write_float32_bits(t(), float()) :: t()
  def write_float32_bits(%__MODULE__{} = writer, value) do
    # Convert float to its 32-bit integer representation
    <<int_value::little-unsigned-32>> = <<value::little-float-32>>
    write_bits(writer, int_value, 32)
  end

  @doc """
  Write a uint64 into the continuous bit stream (not byte-aligned).

  Use this when writing in the middle of a bit-packed packet structure.
  """
  @spec write_uint64_bits(t(), non_neg_integer()) :: t()
  def write_uint64_bits(%__MODULE__{} = writer, value) do
    write_bits(writer, value, 64)
  end

  @doc """
  Write a uint32 into the continuous bit stream (not byte-aligned).

  Use this when writing in the middle of a bit-packed packet structure.
  """
  @spec write_uint32_bits(t(), non_neg_integer()) :: t()
  def write_uint32_bits(%__MODULE__{} = writer, value) do
    write_bits(writer, value, 32)
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
    |> write_float32_bits(x)
    |> write_float32_bits(y)
    |> write_float32_bits(z)
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

  @doc "Write a UTF-16LE string with uint32 length prefix (legacy format)."
  @spec write_wide_string_legacy(t(), String.t()) :: t()
  def write_wide_string_legacy(%__MODULE__{} = writer, string) when is_binary(string) do
    utf16 = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})
    length = String.length(string)

    writer
    |> write_uint32(length)
    |> write_bytes(utf16)
  end

  @doc "Write specified number of bits."
  @spec write_bits(t(), non_neg_integer(), pos_integer()) :: t()
  def write_bits(%__MODULE__{} = writer, value, count) when count > 0 do
    write_bits_acc(writer, value, count)
  end

  @doc "Flush any remaining bits to the buffer."
  @spec flush_bits(t()) :: t()
  def flush_bits(%__MODULE__{bit_pos: 0} = writer), do: writer

  def flush_bits(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer) when bit_pos > 0 do
    writer
    |> append_bytes(<<bit_value>>)
    |> Map.put(:bit_pos, 0)
    |> Map.put(:bit_value, 0)
  end

  # Private functions

  defp append_bytes(%__MODULE__{buffer: buffer} = writer, bytes) do
    %{writer | buffer: [buffer, bytes]}
  end

  defp write_bits_acc(writer, _value, 0), do: writer

  defp write_bits_acc(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer, value, remaining) do
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
