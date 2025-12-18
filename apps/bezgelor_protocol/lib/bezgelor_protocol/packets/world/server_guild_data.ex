defmodule BezgelorProtocol.Packets.World.ServerGuildData do
  @moduledoc """
  Full guild data sent on login.

  ## Wire Format
  has_guild     : uint8 (bool)
  [if has_guild]
  guild_id      : uint32
  name_len      : uint8
  name          : string
  tag           : string (4 bytes)
  motd_len      : uint16
  motd          : string
  influence     : uint32
  rank_count    : uint8
  ranks         : [RankEntry] * rank_count
  member_count  : uint16
  members       : [MemberEntry] * member_count

  RankEntry:
    rank_index  : uint8
    name_len    : uint8
    name        : string
    permissions : uint16

  MemberEntry:
    character_id : uint32
    name_len     : uint8
    name         : string
    rank_index   : uint8
    online       : uint8 (bool)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct has_guild: false,
            guild_id: 0,
            name: "",
            tag: "",
            motd: "",
            influence: 0,
            ranks: [],
            members: []

  @impl true
  def opcode, do: :server_guild_data

  @impl true
  def write(%__MODULE__{has_guild: false}, writer) do
    writer = PacketWriter.write_u8(writer, 0)
    {:ok, writer}
  end

  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(1)
      |> PacketWriter.write_u32(packet.guild_id)
      |> PacketWriter.write_u8(byte_size(packet.name))
      |> PacketWriter.write_bytes_bits(packet.name)
      |> PacketWriter.write_bytes_bits(packet.tag)
      |> PacketWriter.write_u16(byte_size(packet.motd))
      |> PacketWriter.write_bytes_bits(packet.motd)
      |> PacketWriter.write_u32(packet.influence)
      |> PacketWriter.write_u8(length(packet.ranks))

    writer =
      Enum.reduce(packet.ranks, writer, fn rank, w ->
        w
        |> PacketWriter.write_u8(rank.rank_index)
        |> PacketWriter.write_u8(byte_size(rank.name))
        |> PacketWriter.write_bytes_bits(rank.name)
        |> PacketWriter.write_u16(rank.permissions)
      end)

    writer = PacketWriter.write_u16(writer, length(packet.members))

    writer =
      Enum.reduce(packet.members, writer, fn member, w ->
        w
        |> PacketWriter.write_u32(member.character_id)
        |> PacketWriter.write_u8(byte_size(member.name))
        |> PacketWriter.write_bytes_bits(member.name)
        |> PacketWriter.write_u8(member.rank_index)
        |> PacketWriter.write_u8(if(member.online, do: 1, else: 0))
      end)

    {:ok, writer}
  end
end
