defmodule BezgelorProtocol.Packets.World.ServerReputationUpdate do
  @moduledoc """
  Reputation change notification.

  ## Wire Format
  faction_id  : uint32
  standing    : int32 (new total)
  delta       : int32 (change amount, can be negative)
  level       : uint8 (new level)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:faction_id, :standing, :delta, :level]

  @impl true
  def opcode, do: :server_reputation_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.faction_id)
      |> PacketWriter.write_int32(packet.standing)
      |> PacketWriter.write_int32(packet.delta)
      |> PacketWriter.write_byte(level_to_int(packet.level))

    {:ok, writer}
  end

  defp level_to_int(:hated), do: 0
  defp level_to_int(:hostile), do: 1
  defp level_to_int(:unfriendly), do: 2
  defp level_to_int(:neutral), do: 3
  defp level_to_int(:friendly), do: 4
  defp level_to_int(:honored), do: 5
  defp level_to_int(:revered), do: 6
  defp level_to_int(:exalted), do: 7
  defp level_to_int(_), do: 3
end
