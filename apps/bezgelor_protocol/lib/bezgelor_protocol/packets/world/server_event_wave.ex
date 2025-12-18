defmodule BezgelorProtocol.Packets.World.ServerEventWave do
  @moduledoc """
  Notify clients of wave progression in wave-based events.

  ## Wire Format
  instance_id     : uint32
  wave_number     : uint8
  total_waves     : uint8
  wave_type       : uint8 (0=normal, 1=elite, 2=boss, 3=final)
  spawn_count     : uint16
  time_until_next : uint32 (milliseconds, 0 if final wave)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :wave_number, :total_waves, :wave_type, :spawn_count, :time_until_next]

  @impl true
  def opcode, do: 0x0A05

  @doc "Create a wave update packet."
  def new(instance_id, wave_number, total_waves, opts \\ []) do
    %__MODULE__{
      instance_id: instance_id,
      wave_number: wave_number,
      total_waves: total_waves,
      wave_type: Keyword.get(opts, :wave_type, :normal),
      spawn_count: Keyword.get(opts, :spawn_count, 0),
      time_until_next: Keyword.get(opts, :time_until_next, 0)
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.instance_id)
      |> PacketWriter.write_u8(packet.wave_number)
      |> PacketWriter.write_u8(packet.total_waves)
      |> PacketWriter.write_u8(wave_type_to_int(packet.wave_type))
      |> PacketWriter.write_u16(packet.spawn_count)
      |> PacketWriter.write_u32(packet.time_until_next)

    {:ok, writer}
  end

  defp wave_type_to_int(:normal), do: 0
  defp wave_type_to_int(:elite), do: 1
  defp wave_type_to_int(:boss), do: 2
  defp wave_type_to_int(:final), do: 3
  defp wave_type_to_int(_), do: 0

  @doc "Wave types."
  def wave_types, do: [:normal, :elite, :boss, :final]
end
