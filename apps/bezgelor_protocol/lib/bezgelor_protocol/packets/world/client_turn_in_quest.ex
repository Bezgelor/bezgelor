defmodule BezgelorProtocol.Packets.World.ClientTurnInQuest do
  @moduledoc """
  Client turns in a completed quest.

  ## Wire Format
  quest_id    : uint32
  npc_guid    : uint64
  reward_choice : uint8 (for quests with choice rewards)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:quest_id, :npc_guid, :reward_choice]

  @impl true
  def opcode, do: :client_turn_in_quest

  @impl true
  def read(reader) do
    with {:ok, quest_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, npc_guid, reader} <- PacketReader.read_uint64(reader),
         {:ok, reward_choice, reader} <- PacketReader.read_byte(reader) do
      packet = %__MODULE__{
        quest_id: quest_id,
        npc_guid: npc_guid,
        reward_choice: reward_choice
      }

      {:ok, packet, reader}
    end
  end
end
