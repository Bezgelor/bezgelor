defmodule BezgelorProtocol.Packets.World.ServerCinematicActorAttach do
  @moduledoc """
  Attach camera to an actor during a cinematic.

  ## Wire Format

  ```
  attach_type : uint32 - type of attachment
  attach_id   : uint32 - attachment point ID
  delay       : uint32 - delay in ms from cinematic start
  parent_unit : uint32 - unit to attach to
  use_rotation: bool   - use parent's rotation
  ```

  Opcode: 0x0213
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          attach_type: non_neg_integer(),
          attach_id: non_neg_integer(),
          delay: non_neg_integer(),
          parent_unit: non_neg_integer(),
          use_rotation: boolean()
        }

  defstruct attach_type: 0,
            attach_id: 0,
            delay: 0,
            parent_unit: 0,
            use_rotation: false

  @impl true
  def opcode, do: :server_cinematic_actor_attach

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.attach_type)
      |> PacketWriter.write_uint32(packet.attach_id)
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint32(packet.parent_unit)
      |> PacketWriter.write_bits(bool_to_int(packet.use_rotation), 1)

    {:ok, writer}
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
