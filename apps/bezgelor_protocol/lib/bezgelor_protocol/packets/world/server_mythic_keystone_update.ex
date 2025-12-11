defmodule BezgelorProtocol.Packets.World.ServerMythicKeystoneUpdate do
  @moduledoc """
  Keystone has been upgraded, depleted, or modified.

  ## Wire Format
  keystone_id    : uint64
  instance_id    : uint32
  old_level      : uint8
  new_level      : uint8
  depleted       : uint8   (0/1)
  affix_count    : uint8
  affix_ids      : [uint32] * count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :keystone_id,
    :instance_id,
    old_level: 0,
    new_level: 0,
    depleted: false,
    affix_ids: []
  ]

  @impl true
  def opcode, do: 0x0B32

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.keystone_id)
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(packet.old_level)
      |> PacketWriter.write_byte(packet.new_level)
      |> PacketWriter.write_byte(if(packet.depleted, do: 1, else: 0))
      |> PacketWriter.write_byte(length(packet.affix_ids))

    writer =
      Enum.reduce(packet.affix_ids, writer, fn affix_id, w ->
        PacketWriter.write_uint32(w, affix_id)
      end)

    {:ok, writer}
  end
end
