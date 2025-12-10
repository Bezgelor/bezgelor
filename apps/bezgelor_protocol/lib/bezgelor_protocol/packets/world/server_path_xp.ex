defmodule BezgelorProtocol.Packets.World.ServerPathXp do
  @moduledoc """
  Path XP gained notification.

  ## Wire Format
  xp_gained : uint32
  total_xp  : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:xp_gained, :total_xp]

  @impl true
  def opcode, do: :server_path_xp

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.xp_gained)
      |> PacketWriter.write_uint32(packet.total_xp)

    {:ok, writer}
  end
end
