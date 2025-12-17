defmodule BezgelorProtocol.Packets.World.ServerCinematicShowAnimate do
  @moduledoc """
  Control UI visibility and animation during a cinematic.

  ## Wire Format

  ```
  delay  : uint32 - delay in ms from cinematic start
  show   : bool   - show UI elements
  animate: bool   - animate the transition
  ```

  Opcode: 0x022E
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          show: boolean(),
          animate: boolean()
        }

  defstruct delay: 0,
            show: false,
            animate: false

  @impl true
  def opcode, do: :server_cinematic_show_animate

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.delay)
      |> PacketWriter.write_bits(bool_to_int(packet.show), 1)
      |> PacketWriter.write_bits(bool_to_int(packet.animate), 1)

    {:ok, writer}
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
