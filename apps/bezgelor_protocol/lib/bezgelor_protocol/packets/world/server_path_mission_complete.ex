defmodule BezgelorProtocol.Packets.World.ServerPathMissionComplete do
  @moduledoc """
  Path mission completed notification.

  ## Wire Format
  mission_id : uint32
  xp_reward  : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:mission_id, :xp_reward]

  @impl true
  def opcode, do: :server_path_mission_complete

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.mission_id)
      |> PacketWriter.write_u32(packet.xp_reward || 0)

    {:ok, writer}
  end
end
