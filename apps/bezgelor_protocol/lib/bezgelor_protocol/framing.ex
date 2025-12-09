defmodule BezgelorProtocol.Framing do
  @moduledoc """
  Packet framing for WildStar protocol.

  ## Overview

  Handles assembling and disassembling packets from/to the wire format.
  Packets are length-prefixed with a 6-byte header.

  ## Wire Format

      ┌──────────────┬──────────────┬─────────────────────┐
      │ Size (4 bytes)│ Opcode (2 bytes)│ Payload (variable) │
      └──────────────┴──────────────┴─────────────────────┘

  Size includes itself (4 bytes), so payload_length = size - 4.
  """

  alias BezgelorProtocol.Packet

  @header_size Packet.header_size()

  @doc """
  Frame a packet payload with header for transmission.

  Returns the complete packet binary ready to send.
  """
  @spec frame_packet(non_neg_integer(), binary()) :: binary()
  def frame_packet(opcode, payload) when is_binary(payload) do
    size = Packet.packet_size(byte_size(payload))
    header = Packet.build_header(size, opcode)
    header <> payload
  end

  @doc """
  Parse packets from a binary buffer.

  Returns `{:ok, packets, remaining}` where:
  - `packets` is a list of `{opcode, payload}` tuples
  - `remaining` is any leftover data (incomplete packet)

  This function extracts as many complete packets as possible.
  """
  @spec parse_packets(binary()) :: {:ok, [{non_neg_integer(), binary()}], binary()}
  def parse_packets(data) when is_binary(data) do
    parse_packets_acc(data, [])
  end

  defp parse_packets_acc(data, acc) when byte_size(data) < @header_size do
    {:ok, Enum.reverse(acc), data}
  end

  defp parse_packets_acc(data, acc) do
    case Packet.parse_header(binary_part(data, 0, @header_size)) do
      {:ok, size, opcode} ->
        payload_size = Packet.payload_size(size)
        total_size = @header_size + payload_size

        if byte_size(data) >= total_size do
          payload = binary_part(data, @header_size, payload_size)
          remaining = binary_part(data, total_size, byte_size(data) - total_size)
          parse_packets_acc(remaining, [{opcode, payload} | acc])
        else
          {:ok, Enum.reverse(acc), data}
        end

      {:error, _} ->
        {:ok, Enum.reverse(acc), data}
    end
  end
end
