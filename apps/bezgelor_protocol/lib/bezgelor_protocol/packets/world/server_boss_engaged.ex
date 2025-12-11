defmodule BezgelorProtocol.Packets.World.ServerBossEngaged do
  @moduledoc """
  Boss encounter has started.

  ## Wire Format
  boss_id        : uint32
  boss_guid      : uint64
  name_length    : uint8
  name           : string
  health_current : uint64
  health_max     : uint64
  phase          : uint8
  enrage_timer   : uint32  (seconds until enrage, 0 = no enrage)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :boss_id,
    :boss_guid,
    :name,
    :health_current,
    :health_max,
    phase: 1,
    enrage_timer: 0
  ]

  @impl true
  def opcode, do: 0x0B11

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    name_bytes = packet.name || ""

    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_uint64(packet.boss_guid)
      |> PacketWriter.write_byte(byte_size(name_bytes))
      |> PacketWriter.write_wide_string(name_bytes)
      |> PacketWriter.write_uint64(packet.health_current)
      |> PacketWriter.write_uint64(packet.health_max)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_uint32(packet.enrage_timer)

    {:ok, writer}
  end
end
