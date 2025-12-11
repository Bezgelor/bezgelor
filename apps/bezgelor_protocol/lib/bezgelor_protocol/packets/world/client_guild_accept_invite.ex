defmodule BezgelorProtocol.Packets.World.ClientGuildAcceptInvite do
  @moduledoc """
  Accept a pending guild invite.

  ## Wire Format
  guild_id    : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:guild_id]

  @impl true
  def opcode, do: :client_guild_accept_invite

  @impl true
  def read(reader) do
    with {:ok, guild_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{guild_id: guild_id}, reader}
    end
  end
end
