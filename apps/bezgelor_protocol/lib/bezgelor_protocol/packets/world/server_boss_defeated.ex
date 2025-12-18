defmodule BezgelorProtocol.Packets.World.ServerBossDefeated do
  @moduledoc """
  Boss has been defeated.

  ## Wire Format
  boss_id         : uint32
  boss_guid       : uint64
  fight_duration  : uint32  (seconds)
  is_final_boss   : uint8
  loot_method     : uint8   (0=personal, 1=need_greed, 2=master, 3=round_robin)
  lockout_created : uint8   (0/1 - was a lockout created for this kill)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :boss_id,
    :boss_guid,
    fight_duration: 0,
    is_final_boss: false,
    loot_method: :personal,
    lockout_created: false
  ]

  @impl true
  def opcode, do: 0x0B13

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.boss_id)
      |> PacketWriter.write_u64(packet.boss_guid)
      |> PacketWriter.write_u32(packet.fight_duration)
      |> PacketWriter.write_u8(if(packet.is_final_boss, do: 1, else: 0))
      |> PacketWriter.write_u8(loot_method_to_int(packet.loot_method))
      |> PacketWriter.write_u8(if(packet.lockout_created, do: 1, else: 0))

    {:ok, writer}
  end

  defp loot_method_to_int(:personal), do: 0
  defp loot_method_to_int(:need_greed), do: 1
  defp loot_method_to_int(:master), do: 2
  defp loot_method_to_int(:round_robin), do: 3
  defp loot_method_to_int(_), do: 0
end
