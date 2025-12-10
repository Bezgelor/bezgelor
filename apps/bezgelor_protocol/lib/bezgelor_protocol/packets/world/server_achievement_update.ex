defmodule BezgelorProtocol.Packets.World.ServerAchievementUpdate do
  @moduledoc """
  Achievement progress updated.

  ## Wire Format
  achievement_id : uint32
  progress       : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:achievement_id, :progress]

  @impl true
  def opcode, do: :server_achievement_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.achievement_id)
      |> PacketWriter.write_uint32(packet.progress)

    {:ok, writer}
  end
end
