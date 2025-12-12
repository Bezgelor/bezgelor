defmodule BezgelorProtocol.Packets.World.ServerQuestOffer do
  @moduledoc """
  Server offers quests to the client from an NPC.

  Sent when player interacts with a quest giver NPC.

  ## Wire Format
  npc_guid    : uint64 (the NPC offering quests)
  quest_count : uint8
  quests      : [QuestOfferEntry] * quest_count

  QuestOfferEntry:
    quest_id   : uint32
    title_text : uint32 (localized text ID for quest title)
    level      : uint8 (recommended level)
    type       : uint8 (quest type)
    flags      : uint8 (daily, repeatable, etc.)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct npc_guid: 0,
            quests: []

  @impl true
  def opcode, do: :server_quest_offer

  @impl true
  def write(%__MODULE__{npc_guid: npc_guid, quests: quests}, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(npc_guid)
      |> PacketWriter.write_byte(length(quests))

    writer =
      Enum.reduce(quests, writer, fn quest, w ->
        w
        |> PacketWriter.write_uint32(quest.id)
        |> PacketWriter.write_uint32(quest.title_text_id || 0)
        |> PacketWriter.write_byte(quest.level || 1)
        |> PacketWriter.write_byte(quest.type || 0)
        |> PacketWriter.write_byte(quest.flags || 0)
      end)

    {:ok, writer}
  end
end
