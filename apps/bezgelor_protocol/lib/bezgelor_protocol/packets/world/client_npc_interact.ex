defmodule BezgelorProtocol.Packets.World.ClientNpcInteract do
  @moduledoc """
  Client interacts with an NPC (right-click or interact key).

  This packet triggers NPC interaction logic:
  - Quest giver: opens quest dialog
  - Vendor: opens shop
  - Gossip: shows dialogue options

  ## Wire Format
  npc_guid : uint64 (entity GUID of the NPC)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:npc_guid]

  @impl true
  def opcode, do: :client_npc_interact

  @impl true
  def read(reader) do
    with {:ok, npc_guid, reader} <- PacketReader.read_uint64(reader) do
      packet = %__MODULE__{npc_guid: npc_guid}
      {:ok, packet, reader}
    end
  end
end
