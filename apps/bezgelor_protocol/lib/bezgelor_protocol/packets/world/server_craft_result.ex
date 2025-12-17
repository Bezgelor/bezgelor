defmodule BezgelorProtocol.Packets.World.ServerCraftResult do
  @moduledoc """
  Result of a completed craft.

  ## Wire Format
  result        : uint8   - 0 = success, 1 = failed, 2 = critical, 3 = cancelled
  item_id       : uint32  - Crafted item (0 if failed)
  quantity      : uint16  - Quantity crafted
  variant_id    : uint32  - Variant discovered (0 if none)
  xp_gained     : uint32  - Tradeskill XP gained
  quality       : uint8   - 0 = poor, 1 = standard, 2 = good, 3 = excellent
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :item_id, :quantity, :variant_id, :xp_gained, :quality]

  @type result :: :success | :failed | :critical | :cancelled

  @type t :: %__MODULE__{
          result: result(),
          item_id: non_neg_integer(),
          quantity: non_neg_integer(),
          variant_id: non_neg_integer(),
          xp_gained: non_neg_integer(),
          quality: atom()
        }

  @impl true
  def opcode, do: :server_craft_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(result_to_int(packet.result))
      |> PacketWriter.write_u32(packet.item_id || 0)
      |> PacketWriter.write_u16(packet.quantity || 0)
      |> PacketWriter.write_u32(packet.variant_id || 0)
      |> PacketWriter.write_u32(packet.xp_gained || 0)
      |> PacketWriter.write_u8(quality_to_int(packet.quality))

    {:ok, writer}
  end

  defp result_to_int(:success), do: 0
  defp result_to_int(:failed), do: 1
  defp result_to_int(:critical), do: 2
  defp result_to_int(:cancelled), do: 3
  defp result_to_int(_), do: 0

  defp quality_to_int(:poor), do: 0
  defp quality_to_int(:standard), do: 1
  defp quality_to_int(:good), do: 2
  defp quality_to_int(:excellent), do: 3
  defp quality_to_int(_), do: 1
end
