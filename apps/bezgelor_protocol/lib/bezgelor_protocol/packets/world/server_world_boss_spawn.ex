defmodule BezgelorProtocol.Packets.World.ServerWorldBossSpawn do
  @moduledoc """
  Notify zone of world boss spawn.

  ## Wire Format
  boss_id       : uint32
  creature_id   : uint64
  position_x    : float32
  position_y    : float32
  position_z    : float32
  health_max    : uint32
  health_current: uint32
  phase         : uint8
  time_limit_ms : uint32 (0 = no limit)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :creature_id, :position, :health_max, :health_current, :phase, :time_limit_ms]

  @impl true
  def opcode, do: 0x0A10

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_uint64(packet.creature_id)
      |> PacketWriter.write_float32(packet.position.x)
      |> PacketWriter.write_float32(packet.position.y)
      |> PacketWriter.write_float32(packet.position.z)
      |> PacketWriter.write_uint32(packet.health_max)
      |> PacketWriter.write_uint32(packet.health_current)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_uint32(packet.time_limit_ms || 0)

    {:ok, writer}
  end
end
