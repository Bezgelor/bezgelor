defmodule BezgelorProtocol.Packets.World.ServerBossPhase do
  @moduledoc """
  Boss phase transition notification.

  ## Wire Format
  boss_guid         : uint64
  old_phase         : uint8
  new_phase         : uint8
  health_percent    : uint8   (0-100)
  transition_type   : uint8   (0=normal, 1=intermission, 2=final)
  mechanic_count    : uint8
  active_mechanics  : [uint32] * count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :boss_guid,
    :old_phase,
    :new_phase,
    :health_percent,
    transition_type: :normal,
    active_mechanics: []
  ]

  @impl true
  def opcode, do: 0x0B12

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.boss_guid)
      |> PacketWriter.write_byte(packet.old_phase)
      |> PacketWriter.write_byte(packet.new_phase)
      |> PacketWriter.write_byte(packet.health_percent)
      |> PacketWriter.write_byte(transition_to_int(packet.transition_type))
      |> PacketWriter.write_byte(length(packet.active_mechanics))

    writer =
      Enum.reduce(packet.active_mechanics, writer, fn mechanic_id, w ->
        PacketWriter.write_uint32(w, mechanic_id)
      end)

    {:ok, writer}
  end

  defp transition_to_int(:normal), do: 0
  defp transition_to_int(:intermission), do: 1
  defp transition_to_int(:final), do: 2
  defp transition_to_int(_), do: 0
end
