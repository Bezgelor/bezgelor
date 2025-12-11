defmodule BezgelorProtocol.Packets.World.ServerWorldBossPhase do
  @moduledoc """
  Notify zone of world boss phase change.

  ## Wire Format
  boss_id         : uint32
  phase           : uint8
  health_percent  : uint8
  ability_count   : uint8
  abilities       : [uint32] * count (ability IDs unlocked this phase)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :phase, :health_percent, abilities: []]

  @impl true
  def opcode, do: 0x0A11

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_byte(packet.health_percent)
      |> PacketWriter.write_byte(length(packet.abilities))

    writer =
      Enum.reduce(packet.abilities, writer, fn ability_id, w ->
        PacketWriter.write_uint32(w, ability_id)
      end)

    {:ok, writer}
  end
end
