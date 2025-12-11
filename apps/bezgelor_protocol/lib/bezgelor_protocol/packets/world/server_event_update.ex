defmodule BezgelorProtocol.Packets.World.ServerEventUpdate do
  @moduledoc """
  Update event objective progress.

  ## Wire Format
  instance_id     : uint32
  objective_index : uint8
  current         : uint32
  target          : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :objective_index, :current, :target]

  @impl true
  def opcode, do: 0x0A02

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(packet.objective_index)
      |> PacketWriter.write_uint32(packet.current)
      |> PacketWriter.write_uint32(packet.target)

    {:ok, writer}
  end
end
