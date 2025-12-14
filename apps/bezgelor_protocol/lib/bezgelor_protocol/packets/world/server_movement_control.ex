defmodule BezgelorProtocol.Packets.World.ServerMovementControl do
  @moduledoc """
  Server packet to set which entity the player controls.

  Sent during world entry to give player control of their character.

  ## Wire Format (from NexusForever)

  ```
  ticket    : uint32 - Movement ticket/sequence number
  immediate : bool   - Whether to apply immediately
  unit_id   : uint32 - Entity GUID of unit to control
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct ticket: 1,
            immediate: true,
            unit_id: 0

  @type t :: %__MODULE__{
          ticket: non_neg_integer(),
          immediate: boolean(),
          unit_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_movement_control

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.ticket, 32)
      |> PacketWriter.write_bits(if(packet.immediate, do: 1, else: 0), 1)
      |> PacketWriter.write_bits(packet.unit_id, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
