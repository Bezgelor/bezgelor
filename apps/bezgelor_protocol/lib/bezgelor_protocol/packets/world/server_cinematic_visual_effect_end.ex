defmodule BezgelorProtocol.Packets.World.ServerCinematicVisualEffectEnd do
  @moduledoc """
  End a visual effect during a cinematic.

  ## Wire Format

  ```
  delay        : uint32 - delay in ms from cinematic start
  visual_handle: uint32 - handle of the effect to end
  ```

  Opcode: 0x0225
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          visual_handle: non_neg_integer()
        }

  defstruct delay: 0,
            visual_handle: 0

  @impl true
  def opcode, do: :server_cinematic_visual_effect_end

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.visual_handle)

    {:ok, writer}
  end
end
