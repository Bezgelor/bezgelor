defmodule BezgelorProtocol.Packets.World.ServerInstanceComplete do
  @moduledoc """
  Instance has been completed.

  ## Wire Format
  instance_id      : uint32
  difficulty       : uint8
  duration_sec     : uint32
  deaths           : uint16
  damage_done      : uint64
  healing_done     : uint64
  rating_earned    : uint16   (for mythic+)
  timed            : uint8    (0/1 - beat the timer?)
  keystone_upgrade : int8     (-3 to +3 levels, 0 if not mythic+)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :instance_id,
    :difficulty,
    duration_sec: 0,
    deaths: 0,
    damage_done: 0,
    healing_done: 0,
    rating_earned: 0,
    timed: false,
    keystone_upgrade: 0
  ]

  @impl true
  def opcode, do: 0x0B14

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Convert keystone_upgrade to signed byte representation
    upgrade_byte =
      cond do
        packet.keystone_upgrade >= 0 -> packet.keystone_upgrade
        true -> 256 + packet.keystone_upgrade
      end

    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(difficulty_to_int(packet.difficulty))
      |> PacketWriter.write_uint32(packet.duration_sec)
      |> PacketWriter.write_uint16(packet.deaths)
      |> PacketWriter.write_uint64(packet.damage_done)
      |> PacketWriter.write_uint64(packet.healing_done)
      |> PacketWriter.write_uint16(packet.rating_earned)
      |> PacketWriter.write_byte(if(packet.timed, do: 1, else: 0))
      |> PacketWriter.write_byte(upgrade_byte)

    {:ok, writer}
  end

  defp difficulty_to_int(:normal), do: 0
  defp difficulty_to_int(:veteran), do: 1
  defp difficulty_to_int(:challenge), do: 2
  defp difficulty_to_int(:mythic_plus), do: 3
  defp difficulty_to_int(_), do: 0
end
