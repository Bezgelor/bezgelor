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

  @doc "Write raw bytes."
  @spec write_bytes(t(), binary()) :: t()
  def write_bytes(%__MODULE__{} = writer, bytes) when is_binary(bytes) do
    writer
    |> flush_bits()
    |> append_bytes(bytes)
  end

  @doc "Write a UTF-16LE string with uint32 length prefix."
  @spec write_wide_string(t(), String.t()) :: t()
  def write_wide_string(%__MODULE__{} = writer, string) when is_binary(string) do
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
