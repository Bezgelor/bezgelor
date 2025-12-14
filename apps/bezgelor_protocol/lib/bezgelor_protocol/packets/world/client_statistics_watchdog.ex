defmodule BezgelorProtocol.Packets.World.ClientStatisticsWatchdog do
  @moduledoc """
  Client watchdog/health check statistics.

  Sent periodically to report client loop timing and property hash.
  The property hash could be used for cheat detection (client vs server state).

  ## Fields

  - `property_hash_seed` - Seed used for property hash calculation
  - `player_properties_hash` - Hash of player unit properties (anti-cheat)
  - `longest_loop_time` - Longest time between watchdog loops
  - `time_to_buffer_middle` - Time to middle of circular buffer (~1000ms when good)
  - `weighted_avg_loop_time` - Weighted average of loop times
  - `weighted_avg_error` - Error in weighted average calculation
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct property_hash_seed: 0,
            player_properties_hash: 0,
            longest_loop_time: 0,
            time_to_buffer_middle: 0.0,
            weighted_avg_loop_time: 0.0,
            weighted_avg_error: 0.0,
            position_related: 0

  @type t :: %__MODULE__{
          property_hash_seed: non_neg_integer(),
          player_properties_hash: non_neg_integer(),
          longest_loop_time: integer(),
          time_to_buffer_middle: float(),
          weighted_avg_loop_time: float(),
          weighted_avg_error: float(),
          position_related: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_statistics_watchdog

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, property_hash_seed, reader} <- PacketReader.read_uint64(reader),
         {:ok, player_properties_hash, reader} <- PacketReader.read_uint64(reader),
         {:ok, longest_loop_time, reader} <- PacketReader.read_uint32(reader),
         {:ok, time_to_buffer_middle, reader} <- PacketReader.read_float32(reader),
         {:ok, weighted_avg_loop_time, reader} <- PacketReader.read_float32(reader),
         {:ok, weighted_avg_error, reader} <- PacketReader.read_float32(reader),
         {:ok, position_related, reader} <- PacketReader.read_uint32(reader) do
      packet = %__MODULE__{
        property_hash_seed: property_hash_seed,
        player_properties_hash: player_properties_hash,
        longest_loop_time: longest_loop_time,
        time_to_buffer_middle: time_to_buffer_middle,
        weighted_avg_loop_time: weighted_avg_loop_time,
        weighted_avg_error: weighted_avg_error,
        position_related: position_related
      }

      {:ok, packet, reader}
    end
  end
end
