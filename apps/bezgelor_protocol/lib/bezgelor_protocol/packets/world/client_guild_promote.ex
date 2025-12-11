defmodule BezgelorProtocol.Packets.World.ClientGuildPromote do
  @moduledoc """
  Promote a guild member.

  ## Wire Format
  target_id   : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_id]

  @impl true
  def opcode, do: :client_guild_promote

  @impl true
  def read(reader) do
    with {:ok, target_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{target_id: target_id}, reader}
    end
  end
end
