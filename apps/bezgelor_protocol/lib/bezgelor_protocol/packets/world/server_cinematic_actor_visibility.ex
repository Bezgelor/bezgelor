defmodule BezgelorProtocol.Packets.World.ServerCinematicActorVisibility do
  @moduledoc """
  Show or hide an actor during a cinematic.

  ## Wire Format

  ```
  delay   : uint32 - delay in ms from cinematic start
  unit_id : uint32 - unit to show/hide
  hide    : bool   - true to hide, false to show
  unknown0: bool   - unknown flag
  ```

  Opcode: 0x0220
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          unit_id: non_neg_integer(),
          hide: boolean(),
          unknown0: boolean()
        }

  defstruct delay: 0,
            unit_id: 0,
            hide: false,
            unknown0: false

  @impl true
  def opcode, do: :server_cinematic_actor_visibility

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.delay)
      |> PacketWriter.write_u32(packet.unit_id)
      |> PacketWriter.write_bits(bool_to_int(packet.hide), 1)
      |> PacketWriter.write_bits(bool_to_int(packet.unknown0), 1)

    {:ok, writer}
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
