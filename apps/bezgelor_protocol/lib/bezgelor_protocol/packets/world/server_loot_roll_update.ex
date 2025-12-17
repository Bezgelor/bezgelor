defmodule BezgelorProtocol.Packets.World.ServerLootRollUpdate do
  @moduledoc """
  Update on loot roll progress (someone rolled).

  ## Wire Format
  loot_id       : uint64
  character_id  : uint64
  roll_type     : uint8   (0=pass, 1=greed, 2=need)
  roll_value    : uint8   (1-100, the actual roll result)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:loot_id, :character_id, :roll_type, :roll_value]

  @impl true
  def opcode, do: 0x0B21

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.loot_id)
      |> PacketWriter.write_u64(packet.character_id)
      |> PacketWriter.write_u8(roll_type_to_int(packet.roll_type))
      |> PacketWriter.write_u8(packet.roll_value)

    {:ok, writer}
  end

  defp roll_type_to_int(:pass), do: 0
  defp roll_type_to_int(:greed), do: 1
  defp roll_type_to_int(:need), do: 2
  defp roll_type_to_int(_), do: 0
end
