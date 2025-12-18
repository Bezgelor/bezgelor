defmodule BezgelorProtocol.Packets.World.ServerEventList do
  @moduledoc """
  List of active events in zone.

  ## Wire Format
  event_count : uint8
  events      : [Event] * count

  Event:
    instance_id : uint32
    event_id    : uint32
    event_type  : uint8
    phase       : uint8
    time_remaining_ms : uint32
    participant_count : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct events: []

  @impl true
  def opcode, do: 0x0A05

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u8(writer, length(packet.events))

    writer =
      Enum.reduce(packet.events, writer, fn event, w ->
        w
        |> PacketWriter.write_u32(event.instance_id)
        |> PacketWriter.write_u32(event.event_id)
        |> PacketWriter.write_u8(event_type_to_int(event.event_type))
        |> PacketWriter.write_u8(event.phase)
        |> PacketWriter.write_u32(event.time_remaining_ms)
        |> PacketWriter.write_u16(event.participant_count)
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
end
