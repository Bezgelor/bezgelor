defmodule BezgelorProtocol.Packets.World.ServerFriendList do
  @moduledoc """
  Full friend list sent to client.

  ## Wire Format
  count   : uint32
  friends : [FriendEntry] * count

  FriendEntry:
    character_id : uint64
    name         : wstring
    level        : uint8
    class        : uint8
    online       : uint8 (0/1)
    zone_id      : uint32
    note         : wstring
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct friends: []

  @impl true
  def opcode, do: :server_friend_list

  @impl true
  def write(%__MODULE__{friends: friends}, writer) do
    writer = PacketWriter.write_u32(writer, length(friends))

    writer =
      Enum.reduce(friends, writer, fn friend, w ->
        w
        |> PacketWriter.write_u64(friend.character_id)
        |> PacketWriter.write_wide_string(friend.name)
        |> PacketWriter.write_u8(friend.level)
        |> PacketWriter.write_u8(friend.class)
        |> PacketWriter.write_u8(if(friend.online, do: 1, else: 0))
        |> PacketWriter.write_u32(friend.zone_id || 0)
        |> PacketWriter.write_wide_string(friend.note || "")
      end)

    {:ok, writer}
  end
end
