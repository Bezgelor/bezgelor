defmodule BezgelorProtocol.Packets.World.ServerGroupFinderMatch do
  @moduledoc """
  Match found notification - prompts player to accept or decline.

  ## Wire Format
  group_id        : uint64
  instance_id     : uint32
  instance_type   : uint8
  difficulty      : uint8
  timeout_seconds : uint8   (time to respond)
  member_count    : uint8
  members         : [Member] * count

  Member:
    character_id  : uint64
    name_length   : uint8
    name          : string
    role          : uint8
    ready         : uint8   (0=pending, 1=accepted, 2=declined)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:group_id, :instance_id, :instance_type, :difficulty, timeout_seconds: 30, members: []]

  @impl true
  def opcode, do: 0x0B02

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.group_id)
      |> PacketWriter.write_u32(packet.instance_id)
      |> PacketWriter.write_u8(instance_type_to_int(packet.instance_type))
      |> PacketWriter.write_u8(difficulty_to_int(packet.difficulty))
      |> PacketWriter.write_u8(packet.timeout_seconds)
      |> PacketWriter.write_u8(length(packet.members))

    writer =
      Enum.reduce(packet.members, writer, fn member, w ->
        name_bytes = member.name || ""

        w
        |> PacketWriter.write_u64(member.character_id)
        |> PacketWriter.write_u8(byte_size(name_bytes))
        |> PacketWriter.write_wide_string(name_bytes)
        |> PacketWriter.write_u8(role_to_int(member.role))
        |> PacketWriter.write_u8(ready_to_int(member.ready))
      end)

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

  defp ready_to_int(:pending), do: 0
  defp ready_to_int(:accepted), do: 1
  defp ready_to_int(:declined), do: 2
  defp ready_to_int(_), do: 0
end
