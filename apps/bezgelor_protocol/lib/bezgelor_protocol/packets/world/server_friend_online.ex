defmodule BezgelorProtocol.Packets.World.ServerFriendOnline do
  @moduledoc """
  Notification when a friend comes online or goes offline.

  ## Wire Format
  character_id : uint64
  name         : wstring
  online       : uint8 (0/1)
  zone_id      : uint32 (only if online)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:character_id, :name, :online, :zone_id]

  @impl true
  def opcode, do: :server_friend_online

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.character_id)
      |> PacketWriter.write_wide_string(packet.name)
      |> PacketWriter.write_byte(if(packet.online, do: 1, else: 0))
      |> PacketWriter.write_uint32(packet.zone_id || 0)

    {:ok, writer}
  end
end
