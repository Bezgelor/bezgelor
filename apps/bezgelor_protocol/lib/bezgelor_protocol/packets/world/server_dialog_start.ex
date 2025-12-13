defmodule BezgelorProtocol.Packets.World.ServerDialogStart do
  @moduledoc """
  Server packet to open dialogue UI for an NPC.

  ## Overview

  The client receives the NPC's entity GUID and looks up the creature's
  gossipSetId from its local game tables to display dialogue text.

  ## Wire Format

  ```
  dialog_unit_id : uint32 - NPC entity GUID
  unused         : bool   - always false
  ```

  Opcode: 0x0357
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          dialog_unit_id: non_neg_integer(),
          unused: boolean()
        }

  defstruct dialog_unit_id: 0,
            unused: false

  @impl true
  def opcode, do: :server_dialog_start

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.dialog_unit_id)
      |> PacketWriter.write_byte(if(packet.unused, do: 1, else: 0))

    {:ok, writer}
  end
end
