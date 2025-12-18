defmodule BezgelorProtocol.Packets.World.ServerCinematicTransition do
  @moduledoc """
  Screen transition effect for cinematics (fade in/out).

  ## Wire Format

  ```
  delay               : uint32 - delay in ms from cinematic start
  flags               : uint32 - transition flags
  end_tran            : uint32 - end transition type
  tran_duration_start : uint16 - start duration in ms
  tran_duration_mid   : uint16 - middle duration in ms
  tran_duration_end   : uint16 - end duration in ms
  ```

  Opcode: 0x0218
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          flags: non_neg_integer(),
          end_tran: non_neg_integer(),
          tran_duration_start: non_neg_integer(),
          tran_duration_mid: non_neg_integer(),
          tran_duration_end: non_neg_integer()
        }

  defstruct delay: 0,
            flags: 0,
            end_tran: 0,
            tran_duration_start: 0,
            tran_duration_mid: 0,
            tran_duration_end: 0

  @impl true
  def opcode, do: :server_cinematic_transition

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.delay)
      |> PacketWriter.write_u32(packet.flags)
      |> PacketWriter.write_u32(packet.end_tran)
      |> PacketWriter.write_u16(packet.tran_duration_start)
      |> PacketWriter.write_u16(packet.tran_duration_mid)
      |> PacketWriter.write_u16(packet.tran_duration_end)

    {:ok, writer}
  end
end
