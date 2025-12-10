defmodule BezgelorProtocol.Packets.World.ClientRemoveFriend do
  @moduledoc """
  Request to remove a friend.

  ## Wire Format
  friend_id : uint64 - Character ID of friend to remove
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:friend_id]

  @impl true
  def opcode, do: :client_remove_friend

  @impl true
  def read(reader) do
    with {:ok, friend_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{friend_id: friend_id}, reader}
    end
  end
end
