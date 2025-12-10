defmodule BezgelorProtocol.Packets.World.ServerQuestUpdate do
  @moduledoc """
  Quest progress updated.

  ## Wire Format
  quest_id        : uint32
  state           : uint8
  objective_index : uint8
  current         : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:quest_id, :state, :objective_index, :current]

  @impl true
  def opcode, do: :server_quest_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.quest_id)
      |> PacketWriter.write_byte(state_to_int(packet.state))
      |> PacketWriter.write_byte(packet.objective_index)
      |> PacketWriter.write_uint16(packet.current)

    {:ok, writer}
  end

  defp state_to_int(:accepted), do: 0
  defp state_to_int(:complete), do: 1
  defp state_to_int(:failed), do: 2
  defp state_to_int(_), do: 0
end
