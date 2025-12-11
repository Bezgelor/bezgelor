defmodule BezgelorProtocol.Packets.World.ClientGuildCreate do
  @moduledoc """
  Create a new guild.

  ## Wire Format
  name_len    : uint8
  name        : string
  tag_len     : uint8
  tag         : string (4 chars)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:name, :tag]

  @impl true
  def opcode, do: :client_guild_create

  @impl true
  def read(reader) do
    with {:ok, name_len, reader} <- PacketReader.read_byte(reader),
         {:ok, name, reader} <- PacketReader.read_bytes(reader, name_len),
         {:ok, tag_len, reader} <- PacketReader.read_byte(reader),
         {:ok, tag, reader} <- PacketReader.read_bytes(reader, tag_len) do
      {:ok, %__MODULE__{name: name, tag: tag}, reader}
    end
  end
end
