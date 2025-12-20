defmodule BezgelorProtocol.Handler.StatisticsWatchdogHandler do
  @moduledoc "Handler for ClientStatisticsWatchdog packets."

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientStatisticsWatchdog

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    character_name = state.session_data[:character_name] || "unknown"

    case ClientStatisticsWatchdog.read(reader) do
      {:ok, packet, _reader} ->
        measurements = %{
          property_hash_seed: packet.property_hash_seed,
          player_properties_hash: packet.player_properties_hash,
          longest_loop_time_ms: packet.longest_loop_time,
          buffer_time_ms: packet.time_to_buffer_middle,
          weighted_avg_loop_time_ms: packet.weighted_avg_loop_time,
          weighted_avg_error: packet.weighted_avg_error
        }

        metadata = %{
          character_id: state.session_data[:character_id],
          character_name: character_name,
          account_id: state.session_data[:account_id]
        }

        :telemetry.execute([:bezgelor, :client, :watchdog], measurements, metadata)

        # Only log if there are performance concerns
        if packet.time_to_buffer_middle > 2000 do
          Logger.warning(
            "[Telemetry] #{character_name} - Client performance issue: " <>
              "buffer time #{Float.round(packet.time_to_buffer_middle, 1)}ms (should be ~1000ms)"
          )
        end

        {:ok, state}

      {:error, reason} ->
        Logger.warning("[Telemetry] Failed to parse watchdog stats: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
