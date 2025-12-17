defmodule BezgelorProtocol.Packets.World.ServerWorldBossKilled do
  @moduledoc """
  Notify zone that world boss was killed.

  ## Wire Format
  boss_id          : uint32
  kill_time_ms     : uint32
  participant_count: uint16
  top_contributor_count : uint8
  top_contributors : [Contributor] * count

  Contributor:
    character_id : uint64
    name_length  : uint16
    name         : string (UTF-16)
    contribution : uint32
    damage_dealt : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :kill_time_ms, :participant_count, top_contributors: []]

  @impl true
  def opcode, do: 0x0A12

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.boss_id)
      |> PacketWriter.write_u32(packet.kill_time_ms)
      |> PacketWriter.write_u16(packet.participant_count)
      |> PacketWriter.write_u8(length(packet.top_contributors))

    writer =
      Enum.reduce(packet.top_contributors, writer, fn contrib, w ->
        w
        |> PacketWriter.write_u64(contrib.character_id)
        |> PacketWriter.write_wide_string(contrib.name)
        |> PacketWriter.write_u32(contrib.contribution)
        |> PacketWriter.write_u32(contrib.damage_dealt)
      end)

    {:ok, writer}
  end
end
