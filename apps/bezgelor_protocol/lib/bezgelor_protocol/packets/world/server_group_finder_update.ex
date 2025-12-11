defmodule BezgelorProtocol.Packets.World.ServerGroupFinderUpdate do
  @moduledoc """
  Queue status update for group finder.

  ## Wire Format
  update_type     : uint8   (0=status, 1=left_queue, 2=not_queued)
  instance_type   : uint8   (only for status)
  difficulty      : uint8   (only for status)
  queue_position  : uint16  (only for status)
  estimated_wait  : uint32  (only for status, in seconds)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:update_type, :instance_type, :difficulty, queue_position: 0, estimated_wait: 0]

  @impl true
  def opcode, do: 0x0B06

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(update_type_to_int(packet.update_type))

    writer =
      case packet.update_type do
        :status ->
          writer
          |> PacketWriter.write_byte(instance_type_to_int(packet.instance_type))
          |> PacketWriter.write_byte(difficulty_to_int(packet.difficulty))
          |> PacketWriter.write_uint16(packet.queue_position)
          |> PacketWriter.write_uint32(packet.estimated_wait)

        _ ->
          writer
      end

    {:ok, writer}
  end

  defp update_type_to_int(:status), do: 0
  defp update_type_to_int(:left_queue), do: 1
  defp update_type_to_int(:not_queued), do: 2
  defp update_type_to_int(_), do: 0

  defp instance_type_to_int(:dungeon), do: 0
  defp instance_type_to_int(:adventure), do: 1
  defp instance_type_to_int(:raid), do: 2
  defp instance_type_to_int(:expedition), do: 3
  defp instance_type_to_int(nil), do: 0
  defp instance_type_to_int(_), do: 0

  defp difficulty_to_int(:normal), do: 0
  defp difficulty_to_int(:veteran), do: 1
  defp difficulty_to_int(:challenge), do: 2
  defp difficulty_to_int(:mythic_plus), do: 3
  defp difficulty_to_int(nil), do: 0
  defp difficulty_to_int(_), do: 0
end
