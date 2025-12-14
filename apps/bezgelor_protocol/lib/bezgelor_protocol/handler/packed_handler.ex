defmodule BezgelorProtocol.Handler.PackedHandler do
  @moduledoc """
  Handles ClientPacked packets (opcode 0x025C).

  This is similar to ClientEncrypted but the inner packet is NOT encrypted.
  Simpler than ClientPackedWorld - no 5-bit prefix, just length + data.

  ## Packet Structure

  - Length: uint32 (total including itself)
  - Data: length - 4 bytes (inner packet: opcode + payload)
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.{Opcode, PacketReader, PacketRegistry}

  require Logger

  @impl true
  def handle(payload, state) do
    case parse_and_dispatch(payload, state) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:reply, opcode, response, new_state} ->
        {:reply, opcode, response, new_state}

      {:reply_encrypted, opcode, response, new_state} ->
        {:reply_encrypted, opcode, response, new_state}

      {:reply_multi, responses, new_state} ->
        {:reply_multi, responses, new_state}

      {:reply_multi_encrypted, responses, new_state} ->
        {:reply_multi_encrypted, responses, new_state}

      {:reply_world_encrypted, opcode, response, new_state} ->
        {:reply_world_encrypted, opcode, response, new_state}

      {:reply_multi_world_encrypted, responses, new_state} ->
        {:reply_multi_world_encrypted, responses, new_state}

      {:error, reason} ->
        Logger.warning("PackedHandler: failed to process - #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp parse_and_dispatch(payload, state) do
    reader = PacketReader.new(payload)

    # Read length (uint32)
    {:ok, length, reader} = PacketReader.read_uint32(reader)

    # Read inner data (length - 4 bytes)
    inner_size = length - 4
    {:ok, inner_data, _reader} = PacketReader.read_bytes(reader, inner_size)

    # Parse inner packet (no decryption needed)
    case parse_inner_packet(inner_data) do
      {:ok, inner_opcode, inner_payload} ->
        case lookup_handler(inner_opcode) do
          {:ok, handler} ->
            Logger.debug(
              "PackedHandler: dispatching #{inner_opcode} (#{byte_size(inner_payload)} bytes)"
            )

            handler.handle(inner_payload, state)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_inner_packet(data) when byte_size(data) < 2 do
    {:error, :packet_too_short}
  end

  defp parse_inner_packet(data) do
    reader = PacketReader.new(data)

    with {:ok, opcode_int, reader} <- PacketReader.read_uint16(reader),
         {:ok, opcode} <- Opcode.from_integer(opcode_int) do
      # Extract remaining bytes from reader
      %{data: data, byte_pos: pos} = reader
      inner_payload = binary_part(data, pos, byte_size(data) - pos)
      {:ok, opcode, inner_payload}
    else
      {:error, :unknown_opcode} ->
        <<opcode_int::little-16, _rest::binary>> = data
        Logger.warning("PackedHandler: unknown inner opcode 0x#{Integer.to_string(opcode_int, 16)}")
        {:error, {:unknown_opcode, opcode_int}}

      error ->
        error
    end
  end

  defp lookup_handler(opcode) do
    case PacketRegistry.lookup(opcode) do
      nil ->
        Logger.warning("PackedHandler: no handler for inner opcode #{opcode}")
        {:error, {:no_handler, opcode}}

      handler ->
        {:ok, handler}
    end
  end
end
