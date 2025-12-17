defmodule BezgelorProtocol.Packets.World.ServerLootSettings do
  @moduledoc """
  Current loot settings for the group/instance.

  ## Wire Format
  loot_method     : uint8   (0=personal, 1=group_loot, 2=need_before_greed, 3=master_loot, 4=round_robin)
  threshold       : uint8   (minimum quality for rolls: 0=common, 1=uncommon, 2=rare, 3=epic, 4=legendary)
  master_looter_id: uint64  (only relevant for master_loot)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:loot_method, threshold: 2, master_looter_id: 0]

  @impl true
  def opcode, do: 0x0B25

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(loot_method_to_int(packet.loot_method))
      |> PacketWriter.write_u8(packet.threshold)
      |> PacketWriter.write_u64(packet.master_looter_id || 0)

    {:ok, writer}
  end

  defp loot_method_to_int(:personal), do: 0
  defp loot_method_to_int(:group_loot), do: 1
  defp loot_method_to_int(:need_before_greed), do: 2
  defp loot_method_to_int(:master_loot), do: 3
  defp loot_method_to_int(:round_robin), do: 4
  defp loot_method_to_int(_), do: 0
end
