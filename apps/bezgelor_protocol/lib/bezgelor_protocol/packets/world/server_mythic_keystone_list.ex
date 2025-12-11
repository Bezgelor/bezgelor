defmodule BezgelorProtocol.Packets.World.ServerMythicKeystoneList do
  @moduledoc """
  List of player's keystones.

  ## Wire Format
  keystone_count : uint8
  keystones      : [Keystone] * count

  Keystone:
    keystone_id  : uint64
    instance_id  : uint32
    level        : uint8
    depleted     : uint8
    affix_count  : uint8
    affix_ids    : [uint32] * affix_count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [keystones: []]

  @impl true
  def opcode, do: 0x0B33

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_byte(writer, length(packet.keystones))

    writer =
      Enum.reduce(packet.keystones, writer, fn keystone, w ->
        w = w
          |> PacketWriter.write_uint64(keystone.keystone_id)
          |> PacketWriter.write_uint32(keystone.instance_id)
          |> PacketWriter.write_byte(keystone.level)
          |> PacketWriter.write_byte(if(keystone.depleted, do: 1, else: 0))
          |> PacketWriter.write_byte(length(keystone.affix_ids))

        Enum.reduce(keystone.affix_ids, w, fn affix_id, w2 ->
          PacketWriter.write_uint32(w2, affix_id)
        end)
      end)

    {:ok, writer}
  end
end
