defmodule BezgelorProtocol.Packets.World.ServerMythicPlusComplete do
  @moduledoc """
  Mythic+ run completion result.

  ## Wire Format
  success         : uint8   (0=failed, 1=success)
  in_time         : uint8   (0=over time, 1=in time)
  completion_time : uint32  (milliseconds)
  time_limit      : uint32  (milliseconds)
  deaths          : uint8
  time_bonus      : uint8   (keystone levels gained: 0-3)
  score           : uint32
  new_key_level   : uint8   (upgraded keystone level)
  new_key_dungeon : uint32  (new dungeon id)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct success: false,
            in_time: false,
            completion_time: 0,
            time_limit: 0,
            deaths: 0,
            time_bonus: 0,
            score: 0,
            new_key_level: 2,
            new_key_dungeon: 0

  @impl true
  def opcode, do: 0x0B31

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(if packet.success, do: 1, else: 0)
      |> PacketWriter.write_u8(if packet.in_time, do: 1, else: 0)
      |> PacketWriter.write_u32(packet.completion_time)
      |> PacketWriter.write_u32(packet.time_limit)
      |> PacketWriter.write_u8(packet.deaths)
      |> PacketWriter.write_u8(packet.time_bonus)
      |> PacketWriter.write_u32(packet.score)
      |> PacketWriter.write_u8(packet.new_key_level)
      |> PacketWriter.write_u32(packet.new_key_dungeon)

    {:ok, writer}
  end
end
