defmodule BezgelorProtocol.Packets.World.ServerEventPhase do
  @moduledoc """
  Notify client of phase change.

  ## Wire Format
  instance_id     : uint32
  phase           : uint8
  objective_count : uint8
  objectives      : [Objective] * count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :phase, objectives: []]

  @impl true
  def opcode, do: 0x0A04

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_byte(length(packet.objectives))

    writer =
      Enum.reduce(packet.objectives, writer, fn obj, w ->
        w
        |> PacketWriter.write_byte(obj.index)
        |> PacketWriter.write_byte(objective_type_to_int(obj.type))
        |> PacketWriter.write_uint32(obj.target)
        |> PacketWriter.write_uint32(obj.current)
      end)

    {:ok, writer}
  end

  defp objective_type_to_int(:kill), do: 0
  defp objective_type_to_int(:kill_boss), do: 1
  defp objective_type_to_int(:collect), do: 2
  defp objective_type_to_int(:interact), do: 3
  defp objective_type_to_int(:defend), do: 4
  defp objective_type_to_int(:escort), do: 5
  defp objective_type_to_int(:survive), do: 6
  defp objective_type_to_int(:territory), do: 7
  defp objective_type_to_int(:damage), do: 8
  defp objective_type_to_int(_), do: 0
end
