defmodule BezgelorProtocol.Packets.World.ClientAcceptQuest do
  @moduledoc """
  Client accepts a quest from NPC.

  ## Wire Format
  quest_id   : uint32
  npc_guid   : uint64
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:quest_id, :npc_guid]

  @impl true
  def opcode, do: :client_accept_quest

  @impl true
  def read(reader) do
    with {:ok, quest_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, npc_guid, reader} <- PacketReader.read_uint64(reader) do
      packet = %__MODULE__{
        quest_id: quest_id,
        npc_guid: npc_guid
      }

      {:ok, packet, reader}
    end
  end
end
