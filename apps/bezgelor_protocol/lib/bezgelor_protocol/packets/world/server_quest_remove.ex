defmodule BezgelorProtocol.Packets.World.ServerQuestRemove do
  @moduledoc """
  Quest removed from log (abandoned or turned in).

  ## Wire Format
  quest_id : uint32
  reason   : uint8 (0=abandoned, 1=completed, 2=failed)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:quest_id, :reason]

  @impl true
  def opcode, do: :server_quest_remove

  @impl true
  def write(%__MODULE__{quest_id: quest_id, reason: reason}, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(quest_id)
      |> PacketWriter.write_u8(reason_to_int(reason))

    {:ok, writer}
  end

  defp reason_to_int(:abandoned), do: 0
  defp reason_to_int(:completed), do: 1
  defp reason_to_int(:failed), do: 2
  defp reason_to_int(_), do: 0
end
