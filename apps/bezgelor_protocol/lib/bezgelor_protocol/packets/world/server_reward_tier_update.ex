defmodule BezgelorProtocol.Packets.World.ServerRewardTierUpdate do
  @moduledoc """
  Real-time reward tier notifications for public events.

  Sent when a player's contribution crosses a tier threshold.

  ## Wire Format
  instance_id     : uint32
  character_id    : uint64
  tier            : uint8 (0=none, 1=bronze, 2=silver, 3=gold)
  contribution    : uint32
  tier_threshold  : uint32
  next_threshold  : uint32 (0 if at gold)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :character_id, :tier, :contribution, :tier_threshold, :next_threshold]

  @impl true
  def opcode, do: 0x0A06

  @doc "Create a tier update for a player achieving bronze."
  def bronze(instance_id, character_id, contribution, threshold) do
    %__MODULE__{
      instance_id: instance_id,
      character_id: character_id,
      tier: :bronze,
      contribution: contribution,
      tier_threshold: threshold,
      next_threshold: trunc(threshold * 2)
    }
  end

  @doc "Create a tier update for a player achieving silver."
  def silver(instance_id, character_id, contribution, threshold) do
    %__MODULE__{
      instance_id: instance_id,
      character_id: character_id,
      tier: :silver,
      contribution: contribution,
      tier_threshold: threshold,
      next_threshold: trunc(threshold * 1.5)
    }
  end

  @doc "Create a tier update for a player achieving gold."
  def gold(instance_id, character_id, contribution, threshold) do
    %__MODULE__{
      instance_id: instance_id,
      character_id: character_id,
      tier: :gold,
      contribution: contribution,
      tier_threshold: threshold,
      next_threshold: 0
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint64(packet.character_id)
      |> PacketWriter.write_byte(tier_to_int(packet.tier))
      |> PacketWriter.write_uint32(packet.contribution)
      |> PacketWriter.write_uint32(packet.tier_threshold)
      |> PacketWriter.write_uint32(packet.next_threshold)

    {:ok, writer}
  end

  defp tier_to_int(:none), do: 0
  defp tier_to_int(:bronze), do: 1
  defp tier_to_int(:silver), do: 2
  defp tier_to_int(:gold), do: 3
  defp tier_to_int(_), do: 0

  @doc "Reward tiers."
  def tiers, do: [:none, :bronze, :silver, :gold]
end
