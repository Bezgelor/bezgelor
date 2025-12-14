defmodule BezgelorProtocol.Packets.World.ClientStatisticsFramerate do
  @moduledoc """
  Client packet reporting framerate/performance statistics.

  Sent periodically by the client to report rendering performance.

  ## Fields

  - `recent_avg_frame_time` - Recent average frame time (lower = better FPS)
  - `highest_frame_time` - Slowest frame time (spike detection)
  - `position_at_slowest` - Player position when slowest frame occurred
  - `game_time_step` - Game time step preceding slowest frame
  - `session_avg_frame_time` - Entire session average frame time
  """

  @behaviour BezgelorProtocol.Packet.Readable

  import Bitwise

  alias BezgelorProtocol.PacketReader

  defstruct recent_avg_frame_time: 0,
            highest_frame_time: 0,
            position_at_slowest: {0.0, 0.0, 0.0},
            game_time_step: 0.0,
            session_avg_frame_time: 0

  @type t :: %__MODULE__{
          recent_avg_frame_time: non_neg_integer(),
          highest_frame_time: non_neg_integer(),
          position_at_slowest: {float(), float(), float()},
          game_time_step: float(),
          session_avg_frame_time: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_statistics_framerate

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, temp1, reader} <- PacketReader.read_uint32(reader),
         {:ok, temp2, reader} <- PacketReader.read_uint32(reader),
         {:ok, position, reader} <- read_position(reader),
         {:ok, game_time_step, reader} <- PacketReader.read_float32(reader),
         {:ok, temp3, reader} <- PacketReader.read_uint32(reader) do
      # Packed with unknown bit in LSB
      recent_avg_frame_time = temp1 >>> 1
      highest_frame_time = temp2 >>> 1
      session_avg_frame_time = temp3 >>> 1

      packet = %__MODULE__{
        recent_avg_frame_time: recent_avg_frame_time,
        highest_frame_time: highest_frame_time,
        position_at_slowest: position,
        game_time_step: game_time_step,
        session_avg_frame_time: session_avg_frame_time
      }

      {:ok, packet, reader}
    end
  end

  # Read Position structure (matches NexusForever Position.Read)
  defp read_position(reader) do
    with {:ok, x, reader} <- PacketReader.read_float32(reader),
         {:ok, y, reader} <- PacketReader.read_float32(reader),
         {:ok, z, reader} <- PacketReader.read_float32(reader) do
      {:ok, {x, y, z}, reader}
    end
  end
end
