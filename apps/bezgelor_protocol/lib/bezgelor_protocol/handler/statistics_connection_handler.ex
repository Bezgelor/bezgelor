defmodule BezgelorProtocol.Handler.StatisticsConnectionHandler do
  @moduledoc "Handler for ClientStatisticsConnection packets."

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientStatisticsConnection

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    character_name = state.session_data[:character_name] || "unknown"

    case ClientStatisticsConnection.read(reader) do
      {:ok, packet, _reader} ->
        measurements = %{
          rtt_ms: packet.average_rtt_ms,
          bytes_received_per_sec: packet.bytes_received_per_sec,
          bytes_sent_per_sec: packet.bytes_sent_per_sec,
          entity_count: packet.unit_hash_table_count
        }

        metadata = %{
          character_id: state.session_data[:character_id],
          character_name: character_name,
          account_id: state.session_data[:account_id]
        }

        :telemetry.execute([:bezgelor, :client, :connection], measurements, metadata)

        Logger.debug(
          "[Telemetry] #{character_name} - RTT: #{packet.average_rtt_ms}ms, " <>
            "recv: #{packet.bytes_received_per_sec} B/s, sent: #{packet.bytes_sent_per_sec} B/s"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.warning("[Telemetry] Failed to parse connection stats: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
