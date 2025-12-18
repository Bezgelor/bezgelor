defmodule BezgelorProtocol.Packets.World.ServerPathLevelUp do
  @moduledoc """
  Path level up notification.

  ## Wire Format
  new_level : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:new_level]

  @impl true
  def opcode, do: :server_path_level_up

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u8(writer, packet.new_level)
    {:ok, writer}
  end
end
