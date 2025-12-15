defmodule BezgelorProtocol.Packets.World.ServerCinematicScene do
  @moduledoc """
  Trigger a scene during a cinematic.

  ## Wire Format

  ```
  delay   : uint32 - delay in ms from cinematic start
  scene_id: uint32 - scene ID to trigger
  ```

  Opcode: 0x0227
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          scene_id: non_neg_integer()
        }

  defstruct delay: 0,
            scene_id: 0

  @impl true
  def opcode, do: :server_cinematic_scene

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.scene_id)

    {:ok, writer}
  end
end
