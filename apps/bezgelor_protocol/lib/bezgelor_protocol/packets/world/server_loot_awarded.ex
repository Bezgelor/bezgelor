defmodule BezgelorProtocol.Packets.World.ServerLootAwarded do
  @moduledoc """
  Loot has been awarded to a player.

  ## Wire Format
  loot_id       : uint64
  item_id       : uint32
  winner_id     : uint64
  winner_name_len: uint8
  winner_name   : string
  award_reason  : uint8   (0=personal, 1=won_roll, 2=master_loot, 3=round_robin)
  winning_roll  : uint8   (roll value if won via roll, 0 otherwise)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:loot_id, :item_id, :winner_id, :winner_name, :award_reason, winning_roll: 0]

  @impl true
  def opcode, do: 0x0B22

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    name_bytes = packet.winner_name || ""

    writer =
      writer
      |> PacketWriter.write_uint64(packet.loot_id)
      |> PacketWriter.write_uint32(packet.item_id)
      |> PacketWriter.write_uint64(packet.winner_id)
      |> PacketWriter.write_byte(byte_size(name_bytes))
      |> PacketWriter.write_wide_string(name_bytes)
      |> PacketWriter.write_byte(award_reason_to_int(packet.award_reason))
      |> PacketWriter.write_byte(packet.winning_roll)

    {:ok, writer}
  end

  defp award_reason_to_int(:personal), do: 0
  defp award_reason_to_int(:won_roll), do: 1
  defp award_reason_to_int(:master_loot), do: 2
  defp award_reason_to_int(:round_robin), do: 3
  defp award_reason_to_int(_), do: 0
end
