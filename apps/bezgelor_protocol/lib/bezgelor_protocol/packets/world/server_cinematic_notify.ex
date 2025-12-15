defmodule BezgelorProtocol.Packets.World.ServerCinematicNotify do
  @moduledoc """
  Notify client that a cinematic is starting or ending.

  ## Wire Format

  ```
  flags        : uint16  - cinematic flags
  cancel       : uint16  - cancel mode
  duration     : uint32  - duration in milliseconds
  cinematic_id : 14 bits - cinematic ID
  ```

  Opcode: 0x0232
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          flags: non_neg_integer(),
          cancel: non_neg_integer(),
          duration: non_neg_integer(),
          cinematic_id: non_neg_integer()
        }

  defstruct flags: 0,
            cancel: 0,
            duration: 0,
            cinematic_id: 0

  @impl true
  def opcode, do: :server_cinematic_notify

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint16(packet.flags)
      |> PacketWriter.write_uint16(packet.cancel)
      |> PacketWriter.write_uint32(packet.duration)
      |> PacketWriter.write_bits(packet.cinematic_id, 14)

    {:ok, writer}
  end
end
