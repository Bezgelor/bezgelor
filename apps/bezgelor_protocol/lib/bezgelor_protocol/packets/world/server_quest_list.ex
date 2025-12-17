defmodule BezgelorProtocol.Packets.World.ServerQuestList do
  @moduledoc """
  Full quest log sent to client on login.

  ## Wire Format
  count  : uint16
  quests : [QuestEntry] * count

  QuestEntry:
    quest_id        : uint32
    state           : uint8 (0=accepted, 1=complete, 2=failed)
    objective_count : uint8
    objectives      : [ObjectiveEntry] * objective_count

  ObjectiveEntry:
    current : uint16
    target  : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct quests: []

  @impl true
  def opcode, do: :server_quest_list

  @impl true
  def write(%__MODULE__{quests: quests}, writer) do
    writer = PacketWriter.write_u16(writer, length(quests))

    writer =
      Enum.reduce(quests, writer, fn quest, w ->
        objectives = get_in(quest.progress, ["objectives"]) || []

        w
        |> PacketWriter.write_u32(quest.quest_id)
        |> PacketWriter.write_u8(state_to_int(quest.state))
        |> PacketWriter.write_u8(length(objectives))
        |> write_objectives(objectives)
      end)

    {:ok, writer}
  end

  defp write_objectives(writer, objectives) do
    Enum.reduce(objectives, writer, fn obj, w ->
      w
      |> PacketWriter.write_u16(obj["current"] || 0)
      |> PacketWriter.write_u16(obj["target"] || 1)
    end)
  end

  defp state_to_int(:accepted), do: 0
  defp state_to_int(:complete), do: 1
  defp state_to_int(:failed), do: 2
  defp state_to_int(_), do: 0
end
