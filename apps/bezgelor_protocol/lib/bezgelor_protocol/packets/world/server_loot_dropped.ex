defmodule BezgelorProtocol.Packets.World.ServerLootDropped do
  @moduledoc """
  Loot has dropped and is available for rolling/looting.

  ## Wire Format
  loot_id       : uint64
  source_guid   : uint64   (boss/chest that dropped it)
  item_id       : uint32
  quality       : uint8    (0=junk, 1=common, 2=uncommon, 3=rare, 4=epic, 5=legendary)
  loot_method   : uint8    (0=personal, 1=need_greed, 2=master, 3=round_robin)
  roll_timeout  : uint8    (seconds to roll, 0 if personal loot)
  eligible_count: uint8
  eligible_ids  : [uint64] * count  (character IDs eligible to roll)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :loot_id,
    :source_guid,
    :item_id,
    quality: :common,
    loot_method: :personal,
    roll_timeout: 30,
    eligible_ids: []
  ]

  @impl true
  def opcode, do: 0x0B20

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.loot_id)
      |> PacketWriter.write_u64(packet.source_guid)
      |> PacketWriter.write_u32(packet.item_id)
      |> PacketWriter.write_u8(quality_to_int(packet.quality))
      |> PacketWriter.write_u8(loot_method_to_int(packet.loot_method))
      |> PacketWriter.write_u8(packet.roll_timeout)
      |> PacketWriter.write_u8(length(packet.eligible_ids))

    writer =
      Enum.reduce(packet.eligible_ids, writer, fn char_id, w ->
        PacketWriter.write_u64(w, char_id)
      end)

    {:ok, writer}
  end

  defp quality_to_int(:junk), do: 0
  defp quality_to_int(:common), do: 1
  defp quality_to_int(:uncommon), do: 2
  defp quality_to_int(:rare), do: 3
  defp quality_to_int(:epic), do: 4
  defp quality_to_int(:legendary), do: 5
  defp quality_to_int(_), do: 1

  defp loot_method_to_int(:personal), do: 0
  defp loot_method_to_int(:need_greed), do: 1
  defp loot_method_to_int(:master), do: 2
  defp loot_method_to_int(:round_robin), do: 3
  defp loot_method_to_int(_), do: 0
end
