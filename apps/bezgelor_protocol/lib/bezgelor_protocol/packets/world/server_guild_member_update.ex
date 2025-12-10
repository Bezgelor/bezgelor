defmodule BezgelorProtocol.Packets.World.ServerGuildMemberUpdate do
  @moduledoc """
  Guild member update (join, leave, rank change, etc).

  ## Wire Format
  update_type   : uint8
  character_id  : uint32
  [if join]
  name_len      : uint8
  name          : string
  rank_index    : uint8
  [if rank change]
  new_rank      : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @update_join 1
  @update_leave 2
  @update_rank_change 3
  @update_online 4
  @update_offline 5

  defstruct [:update_type, :character_id, :name, :rank_index, :online]

  @impl true
  def opcode, do: :server_guild_member_update

  @impl true
  def write(%__MODULE__{update_type: :join} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(@update_join)
      |> PacketWriter.write_uint32(packet.character_id)
      |> PacketWriter.write_byte(byte_size(packet.name))
      |> PacketWriter.write_bytes(packet.name)
      |> PacketWriter.write_byte(packet.rank_index)

    {:ok, writer}
  end

  def write(%__MODULE__{update_type: :leave} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(@update_leave)
      |> PacketWriter.write_uint32(packet.character_id)

    {:ok, writer}
  end

  def write(%__MODULE__{update_type: :rank_change} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(@update_rank_change)
      |> PacketWriter.write_uint32(packet.character_id)
      |> PacketWriter.write_byte(packet.rank_index)

    {:ok, writer}
  end

  def write(%__MODULE__{update_type: :online} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(@update_online)
      |> PacketWriter.write_uint32(packet.character_id)

    {:ok, writer}
  end

  def write(%__MODULE__{update_type: :offline} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(@update_offline)
      |> PacketWriter.write_uint32(packet.character_id)

    {:ok, writer}
  end
end
