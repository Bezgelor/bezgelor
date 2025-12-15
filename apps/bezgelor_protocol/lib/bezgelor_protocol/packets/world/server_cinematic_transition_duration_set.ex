defmodule BezgelorProtocol.Packets.World.ServerCinematicTransitionDurationSet do
  @moduledoc """
  Set transition durations for cinematic effects.

  ## Wire Format

  ```
  type          : uint32 - transition type
  duration_start: uint16 - start duration in ms
  duration_mid  : uint16 - middle duration in ms
  duration_end  : uint16 - end duration in ms
  ```

  Opcode: 0x0222
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          type: non_neg_integer(),
          duration_start: non_neg_integer(),
          duration_mid: non_neg_integer(),
          duration_end: non_neg_integer()
        }

  defstruct type: 0,
            duration_start: 0,
            duration_mid: 0,
            duration_end: 0

  @impl true
  def opcode, do: :server_cinematic_transition_duration_set

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.type)
      |> PacketWriter.write_uint16(packet.duration_start)
      |> PacketWriter.write_uint16(packet.duration_mid)
      |> PacketWriter.write_uint16(packet.duration_end)

    {:ok, writer}
  end
end
