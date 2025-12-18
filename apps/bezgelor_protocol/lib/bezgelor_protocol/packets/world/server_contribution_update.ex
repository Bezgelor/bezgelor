defmodule BezgelorProtocol.Packets.World.ServerContributionUpdate do
  @moduledoc """
  Update player's personal contribution.

  ## Wire Format
  instance_id  : uint32
  contribution : uint32
  reward_tier  : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :contribution, :reward_tier]

  @impl true
  def opcode, do: 0x0A06

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.instance_id)
      |> PacketWriter.write_u32(packet.contribution)
      |> PacketWriter.write_u8(tier_to_int(packet.reward_tier))

    {:ok, writer}
  end

  defp tier_to_int(:participation), do: 0
  defp tier_to_int(:bronze), do: 1
  defp tier_to_int(:silver), do: 2
  defp tier_to_int(:gold), do: 3
  defp tier_to_int(nil), do: 0
  defp tier_to_int(_), do: 0
end
