defmodule BezgelorProtocol.Packets.World.ServerGroupFinderStatus do
  @moduledoc """
  Queue status update sent to clients in the group finder queue.

  ## Wire Format
  status         : uint8   (0=not_queued, 1=queued, 2=match_found, 3=in_group)
  instance_type  : uint8
  difficulty     : uint8
  role           : uint8
  wait_time_sec  : uint32  (estimated wait time)
  queue_position : uint32  (position in queue, 0 if unknown)
  tanks_found    : uint8
  tanks_needed   : uint8
  healers_found  : uint8
  healers_needed : uint8
  dps_found      : uint8
  dps_needed     : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :status,
    :instance_type,
    :difficulty,
    :role,
    wait_time_sec: 0,
    queue_position: 0,
    tanks_found: 0,
    tanks_needed: 1,
    healers_found: 0,
    healers_needed: 1,
    dps_found: 0,
    dps_needed: 3
  ]

  @impl true
  def opcode, do: 0x0B01

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(status_to_int(packet.status))
      |> PacketWriter.write_byte(instance_type_to_int(packet.instance_type))
      |> PacketWriter.write_byte(difficulty_to_int(packet.difficulty))
      |> PacketWriter.write_byte(role_to_int(packet.role))
      |> PacketWriter.write_uint32(packet.wait_time_sec)
      |> PacketWriter.write_uint32(packet.queue_position)
      |> PacketWriter.write_byte(packet.tanks_found)
      |> PacketWriter.write_byte(packet.tanks_needed)
      |> PacketWriter.write_byte(packet.healers_found)
      |> PacketWriter.write_byte(packet.healers_needed)
      |> PacketWriter.write_byte(packet.dps_found)
      |> PacketWriter.write_byte(packet.dps_needed)

    {:ok, writer}
  end

  defp status_to_int(:not_queued), do: 0
  defp status_to_int(:queued), do: 1
  defp status_to_int(:match_found), do: 2
  defp status_to_int(:in_group), do: 3
  defp status_to_int(_), do: 0

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

  defp role_to_int(:tank), do: 0
  defp role_to_int(:healer), do: 1
  defp role_to_int(:dps), do: 2
  defp role_to_int(_), do: 2
end
