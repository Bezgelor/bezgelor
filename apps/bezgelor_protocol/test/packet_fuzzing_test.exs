defmodule BezgelorProtocol.PacketFuzzingTest do
  @moduledoc """
  Property-based tests for packet parsing robustness.

  Uses StreamData to generate random binary data and verifies that
  packet readers handle malformed input gracefully without crashing.
  This tests the security boundary where untrusted client data enters
  the server.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  import Bitwise

  alias BezgelorProtocol.PacketReader

  describe "PacketReader fuzzing" do
    property "read_byte never crashes on arbitrary binary data" do
      check all(data <- binary()) do
        reader = PacketReader.new(data)

        case PacketReader.read_byte(reader) do
          {:ok, byte, _reader} ->
            assert byte >= 0 and byte <= 255

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "read_uint16 never crashes on arbitrary binary data" do
      check all(data <- binary()) do
        reader = PacketReader.new(data)

        case PacketReader.read_uint16(reader) do
          {:ok, value, _reader} ->
            assert value >= 0 and value <= 0xFFFF

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "read_uint32 never crashes on arbitrary binary data" do
      check all(data <- binary()) do
        reader = PacketReader.new(data)

        case PacketReader.read_uint32(reader) do
          {:ok, value, _reader} ->
            assert value >= 0 and value <= 0xFFFFFFFF

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "read_uint64 never crashes on arbitrary binary data" do
      check all(data <- binary()) do
        reader = PacketReader.new(data)

        case PacketReader.read_uint64(reader) do
          {:ok, value, _reader} ->
            assert value >= 0

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "read_bits never crashes with arbitrary bit counts" do
      check all(
              data <- binary(min_length: 0, max_length: 100),
              # Note: read_bits(0) is not supported - use 1..64
              bit_count <- integer(1..64)
            ) do
        reader = PacketReader.new(data)

        case PacketReader.read_bits(reader, bit_count) do
          {:ok, value, _reader} ->
            # Value should fit in the requested bit count
            assert value >= 0
            assert value < 1 <<< bit_count

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "sequential reads never crash on arbitrary data" do
      check all(
              data <- binary(min_length: 0, max_length: 200),
              read_count <- integer(1..20)
            ) do
        reader = PacketReader.new(data)

        # Perform multiple sequential reads
        result =
          Enum.reduce_while(1..read_count, reader, fn _i, reader ->
            case PacketReader.read_uint32(reader) do
              {:ok, _value, reader} -> {:cont, reader}
              {:error, :eof} -> {:halt, :eof}
            end
          end)

        assert result == :eof or is_struct(result, PacketReader)
      end
    end

    property "read_bytes never crashes with arbitrary length requests" do
      check all(
              data <- binary(min_length: 0, max_length: 100),
              length <- integer(0..200)
            ) do
        reader = PacketReader.new(data)

        case PacketReader.read_bytes(reader, length) do
          {:ok, bytes, _reader} ->
            assert byte_size(bytes) == length

          {:error, :eof} ->
            assert true
        end
      end
    end

    property "read_wide_string handles malformed UTF-16 gracefully" do
      check all(data <- binary(min_length: 0, max_length: 500)) do
        reader = PacketReader.new(data)

        # Should either succeed with a string or return an error
        case PacketReader.read_wide_string(reader) do
          {:ok, string, _reader} when is_binary(string) ->
            assert true

          {:error, _reason} ->
            assert true
        end
      end
    end

    property "read_float32 never crashes on arbitrary data" do
      check all(data <- binary(min_length: 0, max_length: 100)) do
        reader = PacketReader.new(data)

        case PacketReader.read_float32(reader) do
          {:ok, value, _reader} when is_float(value) ->
            assert true

          {:ok, value, _reader} when value in [:nan, :infinity, :neg_infinity] ->
            assert true

          {:error, :eof} ->
            assert true
        end
      end
    end
  end

  describe "Handler fuzzing" do
    @moduletag :handler_fuzzing

    property "handlers return valid responses on arbitrary payloads" do
      # List of handlers to test
      handlers = [
        BezgelorProtocol.Handler.KeepAliveHandler,
        BezgelorProtocol.Handler.StatisticsConnectionHandler,
        BezgelorProtocol.Handler.StatisticsFramerateHandler,
        BezgelorProtocol.Handler.StatisticsWatchdogHandler
      ]

      check all(
              payload <- binary(min_length: 0, max_length: 1000),
              handler <- member_of(handlers)
            ) do
        # Create minimal mock state
        state = %{session_data: %{}}

        # Handler should not crash - it should return a valid tuple
        result = handler.handle(payload, state)

        assert match?({:ok, _}, result) or
                 match?({:error, _}, result) or
                 match?({:reply, _, _, _, _}, result) or
                 match?({:reply_world_encrypted, _, _, _}, result)
      end
    end
  end
end
