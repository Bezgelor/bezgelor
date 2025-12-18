defmodule BezgelorProtocol.Packets.World.ServerCinematicActorAngle do
  @moduledoc """
  Set the facing angle of an actor during a cinematic.

  ## Wire Format

  ```
  delay  : uint32 - delay in ms from cinematic start
  unit_id: uint32 - unit to rotate
  angle  : float  - angle in radians
  ```

  Opcode: 0x0230
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          unit_id: non_neg_integer(),
          angle: float()
        }

  defstruct delay: 0,
            unit_id: 0,
            angle: 0.0

  @impl true
  def opcode, do: :server_cinematic_actor_angle

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.delay)
      |> PacketWriter.write_u32(packet.unit_id)
      |> PacketWriter.write_f32(packet.angle)

    {:ok, writer}
  end
end
