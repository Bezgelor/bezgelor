defmodule BezgelorProtocol.Handler.StatisticsFramerateHandler do
  @moduledoc "Handler for ClientStatisticsFramerate packets."

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientStatisticsFramerate

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    character_name = state.session_data[:character_name] || "unknown"

    case ClientStatisticsFramerate.read(reader) do
      {:ok, packet, _reader} ->
        # Convert frame time to FPS (frame_time is in microseconds)
        recent_fps =
          if packet.recent_avg_frame_time > 0,
            do: 1_000_000 / packet.recent_avg_frame_time,
            else: 0

        session_fps =
          if packet.session_avg_frame_time > 0,
            do: 1_000_000 / packet.session_avg_frame_time,
            else: 0

        {x, y, z} = packet.position_at_slowest

        measurements = %{
          recent_avg_frame_time_us: packet.recent_avg_frame_time,
          recent_fps: Float.round(recent_fps, 1),
          highest_frame_time_us: packet.highest_frame_time,
          session_avg_frame_time_us: packet.session_avg_frame_time,
          session_fps: Float.round(session_fps, 1),
          slowest_frame_x: x,
          slowest_frame_y: y,
          slowest_frame_z: z
        }

        metadata = %{
          character_id: state.session_data[:character_id],
          character_name: character_name,
          account_id: state.session_data[:account_id]
        }

        :telemetry.execute([:bezgelor, :client, :framerate], measurements, metadata)

        Logger.debug(
          "[Telemetry] #{character_name} - FPS: #{Float.round(recent_fps, 1)} " <>
            "(session avg: #{Float.round(session_fps, 1)})"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.warning("[Telemetry] Failed to parse framerate stats: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
