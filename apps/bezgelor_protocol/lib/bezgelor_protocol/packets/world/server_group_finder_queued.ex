defmodule BezgelorProtocol.Packets.World.ServerGroupFinderQueued do
  @moduledoc """
  Confirms player has been added to the group finder queue.

  ## Wire Format
  instance_type   : uint8
  difficulty      : uint8
  role_count      : uint8
  roles           : [uint8] * role_count
  queue_position  : uint16
  estimated_wait  : uint32   (seconds)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_type, :difficulty, roles: [], queue_position: 0, estimated_wait: 0]

  @impl true
  def opcode, do: 0x0B05

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(instance_type_to_int(packet.instance_type))
      |> PacketWriter.write_u8(difficulty_to_int(packet.difficulty))
      |> PacketWriter.write_u8(length(packet.roles))

    writer =
      Enum.reduce(packet.roles, writer, fn role, w ->
        PacketWriter.write_u8(w, role_to_int(role))
      end)

    writer =
      writer
      |> PacketWriter.write_u16(packet.queue_position)
      |> PacketWriter.write_u32(packet.estimated_wait)

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

  defp role_to_int(:tank), do: 0
  defp role_to_int(:healer), do: 1
  defp role_to_int(:dps), do: 2
  defp role_to_int(_), do: 2
end
