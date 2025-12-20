defmodule BezgelorProtocol.PacketReader do
  @moduledoc """
  Bit-level packet reader for WildStar protocol.

  ## Overview

  WildStar packets use bit-packed serialization. This reader supports both
  byte-aligned and bit-level reads, maintaining position state.

  ## Example

      reader = PacketReader.new(binary_data)
      {:ok, value, reader} = PacketReader.read_uint32(reader)
      {:ok, bits, reader} = PacketReader.read_bits(reader, 5)
  """

  import Bitwise

  defstruct [:data, :byte_pos, :bit_pos, :bit_value]

  @type t :: %__MODULE__{
          data: binary(),
          byte_pos: non_neg_integer(),
          bit_pos: non_neg_integer(),
          bit_value: non_neg_integer()
        }

  @doc "Create a new reader from binary data."
  @spec new(binary()) :: t()
  def new(data) when is_binary(data) do
    %__MODULE__{
      data: data,
      byte_pos: 0,
      bit_pos: 0,
      bit_value: 0
    }
  end

  @doc "Read a single byte."
  @spec read_byte(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_byte(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 1) do
      {:ok, <<byte>>, reader} -> {:ok, byte, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint16."
  @spec read_uint16(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint16(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 2) do
      {:ok, <<value::little-16>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint32."
  @spec read_uint32(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint32(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 4) do
      {:ok, <<value::little-32>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint64."
  @spec read_uint64(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint64(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 8) do
      {:ok, <<value::little-64>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read a little-endian float32."
  @spec read_float32(t()) :: {:ok, float(), t()} | {:error, :eof}
  def read_float32(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 4) do
      {:ok, <<value::little-float-32>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read specified number of bytes."
  @spec read_bytes(t(), non_neg_integer()) :: {:ok, binary(), t()} | {:error, :eof}
  def read_bytes(%__MODULE__{} = reader, count) when count >= 0 do
    reader = flush_bits(reader)
    read_raw_bytes(reader, count)
  end

  @doc "Read a null-terminated ASCII string."
  @spec read_string(t()) :: {:ok, String.t(), t()} | {:error, :eof}
  def read_string(%__MODULE__{data: data, byte_pos: pos} = reader) do
    reader = flush_bits(reader)

    case find_null(data, pos) do
      {:ok, null_pos} ->
        length = null_pos - pos
        <<_::binary-size(pos), string::binary-size(length), 0, _::binary>> = data
        {:ok, string, %{reader | byte_pos: null_pos + 1}}

      :error ->
        {:error, :eof}
    end
  end

  @doc """
  Read a UTF-16LE string with bit-packed length prefix.

  This matches NexusForever's GamePacketReader.ReadWideString().
  - 1 bit: extended flag
  - 7 or 15 bits: length in bytes
  - length bytes of UTF-16 data
  """
  @spec read_wide_string(t()) :: {:ok, String.t(), t()} | {:error, term()}
  def read_wide_string(%__MODULE__{} = reader) do
    with {:ok, extended, reader} <- read_bit(reader),
         {:ok, length_bits, reader} <- read_bits(reader, if(extended == 1, do: 15, else: 7)),
         length_bytes = length_bits * 2,
         {:ok, utf16_data, reader} <- read_bytes(reader, length_bytes) do
      case :unicode.characters_to_binary(utf16_data, {:utf16, :little}, :utf8) do
        string when is_binary(string) -> {:ok, string, reader}
        _ -> {:error, :invalid_utf16}
      end
    end
  end

  @doc "Read a UTF-16LE string with uint32 length prefix (legacy format)."
  @spec read_wide_string_legacy(t()) :: {:ok, String.t(), t()} | {:error, term()}
  def read_wide_string_legacy(%__MODULE__{} = reader) do
    with {:ok, length, reader} <- read_uint32(reader),
         {:ok, utf16_data, reader} <- read_bytes(reader, length * 2) do
      case :unicode.characters_to_binary(utf16_data, {:utf16, :little}, :utf8) do
        string when is_binary(string) -> {:ok, string, reader}
        _ -> {:error, :invalid_utf16}
      end
    end
  end

  @doc """
  Read a UTF-16LE string with uint16 length prefix (null-terminated).

  This matches NexusForever's GamePacketReader.ReadWideStringFixed().
  Length is character count, data is length * 2 bytes, minus null terminator.
  """
  @spec read_wide_string_fixed(t()) :: {:ok, String.t(), t()} | {:error, term()}
  def read_wide_string_fixed(%__MODULE__{} = reader) do
    with {:ok, length, reader} <- read_uint16(reader),
         {:ok, utf16_data, reader} <- read_bytes(reader, length * 2) do
      # Skip the null terminator (last 2 bytes)
      utf16_without_null =
        if length > 0 and byte_size(utf16_data) >= 2 do
          binary_part(utf16_data, 0, byte_size(utf16_data) - 2)
        else
          utf16_data
        end

      case :unicode.characters_to_binary(utf16_without_null, {:utf16, :little}, :utf8) do
        string when is_binary(string) -> {:ok, string, reader}
        _ -> {:error, :invalid_utf16}
      end
    end
  end

  @doc "Read a single bit."
  @spec read_bit(t()) :: {:ok, 0 | 1, t()} | {:error, :eof}
  def read_bit(%__MODULE__{} = reader) do
    case read_bits(reader, 1) do
      {:ok, value, reader} -> {:ok, value, reader}
      {:error, :eof} -> {:error, :eof}
    end
  end

  @doc "Read specified number of bits."
  @spec read_bits(t(), pos_integer()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_bits(%__MODULE__{} = reader, count) when count > 0 do
    read_bits_acc(reader, count, 0, 0)
  end

  # Private functions

  defp read_raw_bytes(%__MODULE__{data: data, byte_pos: pos} = reader, count) do
    if byte_size(data) >= pos + count do
      <<_::binary-size(pos), bytes::binary-size(count), _::binary>> = data
      {:ok, bytes, %{reader | byte_pos: pos + count}}
    else
      {:error, :eof}
    end
  end

  @doc """
  Reset bit position to next byte boundary.

  If currently in the middle of reading bits, advances to the start of the next byte.
  Used after reading bit-packed fields to resume byte-aligned reading.
  """
  @spec reset_bits(t()) :: t()
  def reset_bits(%__MODULE__{bit_pos: 0} = reader), do: reader

  def reset_bits(%__MODULE__{bit_pos: bit_pos, byte_pos: byte_pos} = reader) when bit_pos > 0 do
    %{reader | bit_pos: 0, bit_value: 0, byte_pos: byte_pos + 1}
  end

  defp flush_bits(%__MODULE__{bit_pos: 0} = reader), do: reader

  defp flush_bits(%__MODULE__{bit_pos: bit_pos, byte_pos: byte_pos} = reader) when bit_pos > 0 do
    %{reader | bit_pos: 0, bit_value: 0, byte_pos: byte_pos + 1}
  end

  defp read_bits_acc(reader, 0, value, _shift), do: {:ok, value, reader}

  defp read_bits_acc(%__MODULE__{bit_pos: 0} = reader, remaining, value, shift) do
    # Need to load a new byte
    case read_raw_bytes(reader, 1) do
      {:ok, <<byte>>, new_reader} ->
        bits_to_read = min(remaining, 8)
        mask = (1 <<< bits_to_read) - 1
        bits = band(byte, mask)
        new_value = bor(value, bsl(bits, shift))
        new_bit_pos = bits_to_read
        new_bit_value = bsr(byte, bits_to_read)

        updated_reader =
          if new_bit_pos == 8 do
            %{new_reader | bit_pos: 0, bit_value: 0}
          else
            %{
              new_reader
              | bit_pos: new_bit_pos,
                bit_value: new_bit_value,
                byte_pos: new_reader.byte_pos - 1
            }
          end

        read_bits_acc(updated_reader, remaining - bits_to_read, new_value, shift + bits_to_read)

      error ->
        error
    end
  end

  defp read_bits_acc(
         %__MODULE__{bit_pos: bit_pos, bit_value: bit_value, byte_pos: byte_pos} = reader,
         remaining,
         value,
         shift
       ) do
    bits_available = 8 - bit_pos
    bits_to_read = min(remaining, bits_available)
    mask = (1 <<< bits_to_read) - 1
    bits = band(bit_value, mask)
    new_value = bor(value, bsl(bits, shift))
    new_bit_pos = bit_pos + bits_to_read
    new_bit_value = bsr(bit_value, bits_to_read)

    updated_reader =
      if new_bit_pos == 8 do
        %{reader | bit_pos: 0, bit_value: 0, byte_pos: byte_pos + 1}
      else
        %{reader | bit_pos: new_bit_pos, bit_value: new_bit_value}
      end

    read_bits_acc(updated_reader, remaining - bits_to_read, new_value, shift + bits_to_read)
  end

  defp find_null(data, pos) do
    case :binary.match(data, <<0>>, scope: {pos, byte_size(data) - pos}) do
      {null_pos, 1} -> {:ok, null_pos}
      :nomatch -> :error
    end
  end
end
