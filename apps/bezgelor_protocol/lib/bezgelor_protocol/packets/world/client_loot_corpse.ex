defmodule BezgelorProtocol.Packets.World.ClientLootCorpse do
  @moduledoc """
  Client request to loot a corpse entity.

  Sent when a player interacts with a corpse to collect loot.

  ## Wire Format
  corpse_guid : uint64 (GUID of the corpse entity to loot)
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:corpse_guid]

  @impl true
  def opcode, do: :client_loot_corpse

  @impl true
  def read(reader) do
    with {:ok, corpse_guid, reader} <- PacketReader.read_uint64(reader) do
      packet = %__MODULE__{corpse_guid: corpse_guid}
      {:ok, packet, reader}
    end
  end
end
