defmodule BezgelorProtocol.Packets.World.ServerCinematicVisualEffect do
  @moduledoc """
  Play a visual effect during a cinematic.

  ## Wire Format

  ```
  delay               : uint32 - delay in ms from cinematic start
  visual_handle       : uint32 - unique handle for this effect instance
  visual_effect_id    : 17 bits - visual effect ID
  unit_id             : uint32 - unit to attach effect to
  position            : Position - position (x, y, z float + rotation quaternion)
  remove_on_camera_end: bool - remove effect when camera sequence ends
  ```

  Opcode: 0x021C
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type position :: %{
          x: float(),
          y: float(),
          z: float(),
          rx: float(),
          ry: float(),
          rz: float(),
          rw: float()
        }

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          visual_handle: non_neg_integer(),
          visual_effect_id: non_neg_integer(),
          unit_id: non_neg_integer(),
          position: position(),
          remove_on_camera_end: boolean()
        }

  defstruct delay: 0,
            visual_handle: 0,
            visual_effect_id: 0,
            unit_id: 0,
            position: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0, rw: 1.0},
            remove_on_camera_end: false

  @impl true
  def opcode, do: :server_cinematic_visual_effect

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    pos = packet.position

    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.visual_handle)
      |> PacketWriter.write_bits(packet.visual_effect_id, 17)
      |> PacketWriter.write_uint32(packet.unit_id)
      # Position
      |> PacketWriter.write_float32(pos.x)
      |> PacketWriter.write_float32(pos.y)
      |> PacketWriter.write_float32(pos.z)
      # Rotation quaternion
      |> PacketWriter.write_float32(pos.rx)
      |> PacketWriter.write_float32(pos.ry)
      |> PacketWriter.write_float32(pos.rz)
      |> PacketWriter.write_float32(pos.rw)
      |> PacketWriter.write_bits(bool_to_int(packet.remove_on_camera_end), 1)

    {:ok, writer}
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
