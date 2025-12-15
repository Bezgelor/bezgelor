defmodule BezgelorProtocol.Packets.World.ServerCinematicCameraSpline do
  @moduledoc """
  Move camera along a spline path during a cinematic.

  ## Wire Format

  ```
  delay       : uint32 - delay in ms from cinematic start
  spline      : uint32 - spline path ID
  spline_mode : uint32 - spline movement mode
  speed       : float  - movement speed along spline
  target      : bool   - whether camera targets a point
  use_rotation: bool   - use spline rotation data
  ```

  Opcode: 0x0215
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          spline: non_neg_integer(),
          spline_mode: non_neg_integer(),
          speed: float(),
          target: boolean(),
          use_rotation: boolean()
        }

  defstruct delay: 0,
            spline: 0,
            spline_mode: 0,
            speed: 1.0,
            target: false,
            use_rotation: false

  @impl true
  def opcode, do: :server_cinematic_camera_spline

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.spline)
      |> PacketWriter.write_uint32(packet.spline_mode)
      |> PacketWriter.write_float32(packet.speed)
      |> PacketWriter.write_bits(bool_to_int(packet.target), 1)
      |> PacketWriter.write_bits(bool_to_int(packet.use_rotation), 1)

    {:ok, writer}
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
