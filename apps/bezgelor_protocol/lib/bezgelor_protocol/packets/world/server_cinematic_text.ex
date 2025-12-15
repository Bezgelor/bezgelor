defmodule BezgelorProtocol.Packets.World.ServerCinematicText do
  @moduledoc """
  Display subtitle text during a cinematic.

  Text entries are added in pairs: one with the text ID at the start time,
  and one with text_id=0 at the end time to hide it.

  ## Wire Format

  ```
  delay   : uint32 - delay in ms from cinematic start
  text_id : uint32 - localized text ID (0 to hide text)
  ```

  Opcode: 0x022A
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          text_id: non_neg_integer()
        }

  defstruct delay: 0,
            text_id: 0

  @impl true
  def opcode, do: :server_cinematic_text

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.text_id)

    {:ok, writer}
  end
end
