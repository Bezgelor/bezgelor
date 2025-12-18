defmodule BezgelorProtocol.Packets.World.ServerEventStart do
  @moduledoc """
  Notify client that a public event has started.

  ## Wire Format
  instance_id     : uint32
  event_id        : uint32
  event_type      : uint8
  phase           : uint8
  duration_ms     : uint32
  objective_count : uint8
  objectives      : [Objective] * count

  Objective:
    index   : uint8
    type    : uint8
    target  : uint32
    current : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :event_id, :event_type, :phase, :duration_ms, objectives: []]

  @impl true
  def opcode, do: 0x0A01

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.instance_id)
      |> PacketWriter.write_u32(packet.event_id)
      |> PacketWriter.write_u8(event_type_to_int(packet.event_type))
      |> PacketWriter.write_u8(packet.phase)
      |> PacketWriter.write_u32(packet.duration_ms)
      |> PacketWriter.write_u8(length(packet.objectives))

    writer =
      Enum.reduce(packet.objectives, writer, fn obj, w ->
        w
        |> PacketWriter.write_u8(obj.index)
        |> PacketWriter.write_u8(objective_type_to_int(obj.type))
        |> PacketWriter.write_u32(obj.target)
        |> PacketWriter.write_u32(obj.current)
      end)

    {:ok, writer}
  end

  defp event_type_to_int(:invasion), do: 0
  defp event_type_to_int(:collection), do: 1
  defp event_type_to_int(:territory), do: 2
  defp event_type_to_int(:defense), do: 3
  defp event_type_to_int(:escort), do: 4
  defp event_type_to_int(:world_boss), do: 5
  defp event_type_to_int(_), do: 0

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
