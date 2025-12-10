defmodule BezgelorProtocol.Packets.World.ServerLootDrop do
  @moduledoc """
  Server notification of loot drops.

  ## Overview

  Sent when a creature dies and generates loot.
  For simplicity, loot is awarded directly to the player.

  ## Wire Format

  ```
  source_guid : uint64 - GUID of entity that dropped loot
  gold        : uint32 - Gold amount
  item_count  : uint32 - Number of items
  items       : array  - Array of loot items:
    item_id   : uint32 - Item template ID
    quantity  : uint32 - Stack count
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:source_guid, :gold, :items]

  @type loot_item :: {non_neg_integer(), non_neg_integer()}

  @type t :: %__MODULE__{
          source_guid: non_neg_integer(),
          gold: non_neg_integer(),
          items: [loot_item()]
        }

  @impl true
  def opcode, do: :server_loot_drop

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    items = packet.items || []

    writer =
      writer
      |> PacketWriter.write_uint64(packet.source_guid)
      |> PacketWriter.write_uint32(packet.gold || 0)
      |> PacketWriter.write_uint32(length(items))

    writer =
      Enum.reduce(items, writer, fn {item_id, quantity}, w ->
        w
        |> PacketWriter.write_uint32(item_id)
        |> PacketWriter.write_uint32(quantity)
      end)

    {:ok, writer}
  end
end
