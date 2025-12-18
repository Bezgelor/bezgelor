defmodule BezgelorProtocol.Packets.World.ServerMythicPlusStatus do
  @moduledoc """
  Mythic+ run status update.

  ## Wire Format
  status          : uint8   (0=in_progress, 1=completed, 2=failed, 3=abandoned)
  elapsed_time    : uint32  (milliseconds)
  time_limit      : uint32  (milliseconds)
  deaths          : uint8
  trash_percent   : uint8   (0-100)
  bosses_killed   : uint8
  bosses_required : uint8
  keystone_level  : uint8
  affix_count     : uint8
  affix_ids       : [uint8] * count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :status,
    :elapsed_time,
    :time_limit,
    deaths: 0,
    trash_percent: 0,
    bosses_killed: 0,
    bosses_required: 0,
    keystone_level: 2,
    affix_ids: []
  ]

  @impl true
  def opcode, do: 0x0B30

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(status_to_int(packet.status))
      |> PacketWriter.write_u32(packet.elapsed_time)
      |> PacketWriter.write_u32(packet.time_limit)
      |> PacketWriter.write_u8(packet.deaths)
      |> PacketWriter.write_u8(packet.trash_percent)
      |> PacketWriter.write_u8(packet.bosses_killed)
      |> PacketWriter.write_u8(packet.bosses_required)
      |> PacketWriter.write_u8(packet.keystone_level)
      |> PacketWriter.write_u8(length(packet.affix_ids))

    writer =
      Enum.reduce(packet.affix_ids, writer, fn id, w ->
        PacketWriter.write_u8(w, id)
      end)

    {:ok, writer}
  end

  defp status_to_int(:in_progress), do: 0
  defp status_to_int(:completed), do: 1
  defp status_to_int(:failed), do: 2
  defp status_to_int(:abandoned), do: 3
  defp status_to_int(_), do: 0
end
