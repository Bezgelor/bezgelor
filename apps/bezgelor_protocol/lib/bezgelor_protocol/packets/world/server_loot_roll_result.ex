defmodule BezgelorProtocol.Packets.World.ServerLootRollResult do
  @moduledoc """
  Result of a loot roll - sent when all players have rolled.

  ## Wire Format
  loot_id       : uint64
  item_id       : uint32
  winner_id     : uint64
  winner_name_len: uint8
  winner_name   : string
  roll_type     : uint8   (0=need, 1=greed, 2=pass)
  roll_value    : uint8   (1-100)
  roll_count    : uint8
  rolls         : [Roll] * count

  Roll:
    character_id  : uint64
    roll_type     : uint8
    roll_value    : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:loot_id, :item_id, :winner_id, :winner_name, :roll_type, :roll_value, rolls: []]

  @impl true
  def opcode, do: 0x0B24

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    name_bytes = packet.winner_name || ""

    writer =
      writer
      |> PacketWriter.write_uint64(packet.loot_id)
      |> PacketWriter.write_uint32(packet.item_id)
      |> PacketWriter.write_uint64(packet.winner_id || 0)
      |> PacketWriter.write_byte(byte_size(name_bytes))
      |> PacketWriter.write_wide_string(name_bytes)
      |> PacketWriter.write_byte(roll_type_to_int(packet.roll_type))
      |> PacketWriter.write_byte(packet.roll_value || 0)
      |> PacketWriter.write_byte(length(packet.rolls))

    writer =
      Enum.reduce(packet.rolls, writer, fn roll, w ->
        w
        |> PacketWriter.write_uint64(roll.character_id)
        |> PacketWriter.write_byte(roll_type_to_int(roll.roll_type))
        |> PacketWriter.write_byte(roll.roll_value)
      end)

    {:ok, writer}
  end

  defp roll_type_to_int(:need), do: 0
  defp roll_type_to_int(:greed), do: 1
  defp roll_type_to_int(:pass), do: 2
  defp roll_type_to_int(_), do: 2
end
