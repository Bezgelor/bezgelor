defmodule BezgelorProtocol.Packets.World.ClientGuildKick do
  @moduledoc """
  Kick a member from guild.

  ## Wire Format
  target_id   : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_id]

  @impl true
  def opcode, do: :client_guild_kick

  @impl true
  def read(reader) do
    with {:ok, target_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{target_id: target_id}, reader}
    end
  end
end
