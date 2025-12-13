defmodule BezgelorProtocol.Packets.World.ClientLootSettings do
  @moduledoc """
  Request to change loot settings.

  ## Wire Format
  loot_method     : uint8
  threshold       : uint8
  master_looter_id: uint64  (optional, for master_loot)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:loot_method, :threshold, :master_looter_id]

  @impl true
  def opcode, do: 0x0A26

  @impl true
  def read(reader) do
    {:ok, loot_method, reader} = PacketReader.read_byte(reader)
    {:ok, threshold, reader} = PacketReader.read_byte(reader)
    {:ok, master_looter_id, reader} = PacketReader.read_uint64(reader)

    packet = %__MODULE__{
      loot_method: loot_method,
      threshold: threshold,
      master_looter_id: master_looter_id
    }

    {:ok, packet, reader}
  end
end
