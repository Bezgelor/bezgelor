defmodule BezgelorProtocol.Packets.World.ClientStatisticsConnection do
  @moduledoc """
  Client packet reporting network connection statistics.

  Sent periodically by the client to report network health metrics.

  ## Fields

  - `average_rtt_ms` - Average round-trip time in milliseconds (ping)
  - `bytes_received_per_sec` - Network receive rate
  - `bytes_sent_per_sec` - Network send rate
  - `unit_hash_table_count` - Number of entities tracked by client
  """

  @behaviour BezgelorProtocol.Packet.Readable

  import Bitwise

  alias BezgelorProtocol.PacketReader

  defstruct average_rtt_ms: 0,
            bytes_received_per_sec: 0,
            bytes_sent_per_sec: 0,
            unit_hash_table_count: 0

  @type t :: %__MODULE__{
          average_rtt_ms: non_neg_integer(),
          bytes_received_per_sec: non_neg_integer(),
          bytes_sent_per_sec: non_neg_integer(),
          unit_hash_table_count: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_statistics_connection

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, average_rtt_ms, reader} <- PacketReader.read_uint32(reader),
         {:ok, bytes_received_per_sec, reader} <- PacketReader.read_uint32(reader),
         {:ok, bytes_sent_per_sec, reader} <- PacketReader.read_uint32(reader),
         {:ok, temp, reader} <- PacketReader.read_uint32(reader) do
      # Lower bit is unknown flag, rest is count
      unit_hash_table_count = temp >>> 1

      packet = %__MODULE__{
        average_rtt_ms: average_rtt_ms,
        bytes_received_per_sec: bytes_received_per_sec,
        bytes_sent_per_sec: bytes_sent_per_sec,
        unit_hash_table_count: unit_hash_table_count
      }

      {:ok, packet, reader}
    end
  end
end
