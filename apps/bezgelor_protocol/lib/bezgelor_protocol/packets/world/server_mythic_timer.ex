defmodule BezgelorProtocol.Packets.World.ServerMythicTimer do
  @moduledoc """
  Mythic+ timer update.

  ## Wire Format
  elapsed_ms       : uint32  (time elapsed since start)
  time_limit_ms    : uint32  (total time limit)
  plus_two_ms      : uint32  (threshold for +2 upgrade)
  plus_three_ms    : uint32  (threshold for +3 upgrade)
  trash_percent    : uint8   (0-100, enemy forces killed)
  trash_required   : uint8   (percent required, usually 100)
  bosses_killed    : uint8
  bosses_total     : uint8
  deaths           : uint16
  death_penalty_ms : uint32  (time penalty from deaths)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    elapsed_ms: 0,
    time_limit_ms: 0,
    plus_two_ms: 0,
    plus_three_ms: 0,
    trash_percent: 0,
    trash_required: 100,
    bosses_killed: 0,
    bosses_total: 0,
    deaths: 0,
    death_penalty_ms: 0
  ]

  @impl true
  def opcode, do: 0x0B31

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.elapsed_ms)
      |> PacketWriter.write_u32(packet.time_limit_ms)
      |> PacketWriter.write_u32(packet.plus_two_ms)
      |> PacketWriter.write_u32(packet.plus_three_ms)
      |> PacketWriter.write_u8(packet.trash_percent)
      |> PacketWriter.write_u8(packet.trash_required)
      |> PacketWriter.write_u8(packet.bosses_killed)
      |> PacketWriter.write_u8(packet.bosses_total)
      |> PacketWriter.write_u16(packet.deaths)
      |> PacketWriter.write_u32(packet.death_penalty_ms)

    {:ok, writer}
  end
end
