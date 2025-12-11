defmodule BezgelorProtocol.Packets.World.ServerInstanceInfo do
  @moduledoc """
  Instance information sent when entering an instance.

  ## Wire Format
  instance_guid    : binary(16)
  instance_id      : uint32
  instance_type    : uint8
  difficulty       : uint8
  zone_id          : uint32
  boss_count       : uint8
  bosses_killed    : uint8
  trash_percent    : uint8   (0-100)
  time_limit_sec   : uint32  (0 = no limit)
  lockout_extends  : uint8   (can extend lockout? 0/1)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :instance_guid,
    :instance_id,
    :instance_type,
    :difficulty,
    :zone_id,
    boss_count: 0,
    bosses_killed: 0,
    trash_percent: 0,
    time_limit_sec: 0,
    lockout_extends: false
  ]

  @impl true
  def opcode, do: 0x0B10

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bytes(packet.instance_guid)
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(instance_type_to_int(packet.instance_type))
      |> PacketWriter.write_byte(difficulty_to_int(packet.difficulty))
      |> PacketWriter.write_uint32(packet.zone_id)
      |> PacketWriter.write_byte(packet.boss_count)
      |> PacketWriter.write_byte(packet.bosses_killed)
      |> PacketWriter.write_byte(packet.trash_percent)
      |> PacketWriter.write_uint32(packet.time_limit_sec)
      |> PacketWriter.write_byte(if(packet.lockout_extends, do: 1, else: 0))

    {:ok, writer}
  end

  defp instance_type_to_int(:dungeon), do: 0
  defp instance_type_to_int(:adventure), do: 1
  defp instance_type_to_int(:raid), do: 2
  defp instance_type_to_int(:expedition), do: 3
  defp instance_type_to_int(_), do: 0

  defp difficulty_to_int(:normal), do: 0
  defp difficulty_to_int(:veteran), do: 1
  defp difficulty_to_int(:challenge), do: 2
  defp difficulty_to_int(:mythic_plus), do: 3
  defp difficulty_to_int(_), do: 0
end
