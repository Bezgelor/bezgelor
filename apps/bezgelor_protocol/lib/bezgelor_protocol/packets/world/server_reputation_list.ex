defmodule BezgelorProtocol.Packets.World.ServerReputationList do
  @moduledoc """
  Full reputation list sent to client.

  ## Wire Format
  count       : uint32
  reputations : [ReputationEntry] * count

  ReputationEntry:
    faction_id : uint32
    standing   : int32 (can be negative)
    level      : uint8 (0-7)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct reputations: []

  @impl true
  def opcode, do: :server_reputation_list

  @impl true
  def write(%__MODULE__{reputations: reputations}, writer) do
    writer = PacketWriter.write_u32(writer, length(reputations))

    writer =
      Enum.reduce(reputations, writer, fn rep, w ->
        w
        |> PacketWriter.write_u32(rep.faction_id)
        |> PacketWriter.write_i32(rep.standing)
        |> PacketWriter.write_u8(level_to_int(rep.level))
      end)

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
