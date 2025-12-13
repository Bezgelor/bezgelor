defmodule BezgelorProtocol.Packets.World.ClientActivateKeystone do
  @moduledoc """
  Player activates a keystone to start a Mythic+ dungeon.

  ## Wire Format
  dungeon_id    : uint32
  keystone_level: uint8
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:dungeon_id, :keystone_level]

  @impl true
  def opcode, do: 0x0A30

  @impl true
  def read(reader) do
    {:ok, dungeon_id, reader} = PacketReader.read_uint32(reader)
    {:ok, keystone_level, reader} = PacketReader.read_byte(reader)

    packet = %__MODULE__{
      dungeon_id: dungeon_id,
      keystone_level: keystone_level
    }

    {:ok, packet, reader}
  end
end
