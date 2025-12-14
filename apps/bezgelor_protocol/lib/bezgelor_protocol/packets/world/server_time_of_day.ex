defmodule BezgelorProtocol.Packets.World.ServerTimeOfDay do
  @moduledoc """
  Server packet with game time information.

  Sent during world entry to set the in-game time of day.

  ## Wire Format (from NexusForever)

  ```
  time_of_day   : uint32 - Current time in seconds (0-86400)
  season        : uint32 - Season (unused in WildStar)
  length_of_day : uint32 - Real seconds per in-game day
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Default: 3.5 hour real time = 1 in-game day
  @default_length_of_day trunc(3.5 * 60 * 60)

  defstruct time_of_day: 0,
            season: 0,
            length_of_day: @default_length_of_day

  @type t :: %__MODULE__{
          time_of_day: non_neg_integer(),
          season: non_neg_integer(),
          length_of_day: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_time_of_day

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.time_of_day, 32)
      |> PacketWriter.write_bits(packet.season, 32)
      |> PacketWriter.write_bits(packet.length_of_day, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc """
  Create a time of day packet for the current real-world time.
  Maps real time to in-game time based on length_of_day setting.
  """
  @spec now(non_neg_integer()) :: t()
  def now(length_of_day \\ @default_length_of_day) do
    # Calculate in-game time based on current UTC time
    now_unix = :os.system_time(:second)
    time_of_day = rem(div(now_unix * 86400, length_of_day), 86400)

    %__MODULE__{
      time_of_day: time_of_day,
      season: 0,
      length_of_day: length_of_day
    }
  end
end
