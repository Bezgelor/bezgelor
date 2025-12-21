defmodule BezgelorProtocol.Packets.World.ServerEventComplete do
  @moduledoc """
  Notify client that event has completed.

  ## Wire Format
  instance_id   : uint32
  event_id      : uint32
  success       : uint8 (0=fail, 1=success)
  reward_tier   : uint8 (0=participation, 1=bronze, 2=silver, 3=gold)
  contribution  : uint32
  reward_xp     : uint32
  reward_gold   : uint32
  reward_count  : uint8
  rewards       : [Reward] * count

  Reward:
    item_id  : uint32
    quantity : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :instance_id,
    :event_id,
    :success,
    :reward_tier,
    :contribution,
    :reward_xp,
    :reward_gold,
    rewards: []
  ]

  @impl true
  def opcode, do: 0x0A03

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.instance_id)
      |> PacketWriter.write_u32(packet.event_id)
      |> PacketWriter.write_u8(if(packet.success, do: 1, else: 0))
      |> PacketWriter.write_u8(tier_to_int(packet.reward_tier))
      |> PacketWriter.write_u32(packet.contribution)
      |> PacketWriter.write_u32(packet.reward_xp)
      |> PacketWriter.write_u32(packet.reward_gold)
      |> PacketWriter.write_u8(length(packet.rewards))

    writer =
      Enum.reduce(packet.rewards, writer, fn reward, w ->
        w
        |> PacketWriter.write_u32(reward.item_id)
        |> PacketWriter.write_u16(reward.quantity)
      end)

    {:ok, writer}
  end

  defp tier_to_int(:participation), do: 0
  defp tier_to_int(:bronze), do: 1
  defp tier_to_int(:silver), do: 2
  defp tier_to_int(:gold), do: 3
  defp tier_to_int(_), do: 0
end
