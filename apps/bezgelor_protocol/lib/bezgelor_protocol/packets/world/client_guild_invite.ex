defmodule BezgelorProtocol.Packets.World.ClientGuildInvite do
  @moduledoc """
  Invite a player to guild.

  ## Wire Format
  target_len  : uint8
  target      : string
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_name]

  @impl true
  def opcode, do: :client_guild_invite

  @impl true
  def read(reader) do
    with {:ok, name_len, reader} <- PacketReader.read_byte(reader),
         {:ok, name, reader} <- PacketReader.read_bytes(reader, name_len) do
      {:ok, %__MODULE__{target_name: name}, reader}
    end
  end
end
