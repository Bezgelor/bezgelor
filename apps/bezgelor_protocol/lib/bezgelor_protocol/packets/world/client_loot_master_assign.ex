defmodule BezgelorProtocol.Packets.World.ClientLootMasterAssign do
  @moduledoc """
  Master looter assigns loot to a player.

  ## Wire Format
  loot_id       : uint64
  recipient_id  : uint64
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:loot_id, :recipient_id]

  @impl true
  def opcode, do: 0x0A25

  @impl true
  def read(reader) do
    {loot_id, reader} = PacketReader.read_uint64(reader)
    {recipient_id, reader} = PacketReader.read_uint64(reader)

    packet = %__MODULE__{
      loot_id: loot_id,
      recipient_id: recipient_id
    }

    {:ok, packet, reader}
  end
end
