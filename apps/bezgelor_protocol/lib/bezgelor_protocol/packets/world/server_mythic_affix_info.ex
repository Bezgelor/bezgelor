defmodule BezgelorProtocol.Packets.World.ServerMythicAffixInfo do
  @moduledoc """
  Active mythic+ affixes for the current run.

  ## Wire Format
  keystone_level : uint8
  affix_count    : uint8
  affixes        : [Affix] * count

  Affix:
    affix_id    : uint32
    tier        : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [keystone_level: 0, affixes: []]

  @impl true
  def opcode, do: 0x0B30

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(packet.keystone_level)
      |> PacketWriter.write_byte(length(packet.affixes))

    writer =
      Enum.reduce(packet.affixes, writer, fn affix, w ->
        w
        |> PacketWriter.write_uint32(affix.affix_id)
        |> PacketWriter.write_byte(affix.tier)
      end)

    {:ok, writer}
  end
end
