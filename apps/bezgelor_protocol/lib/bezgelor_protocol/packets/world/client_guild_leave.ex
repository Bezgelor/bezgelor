defmodule BezgelorProtocol.Packets.World.ClientGuildLeave do
  @moduledoc """
  Leave current guild.

  ## Wire Format
  (empty - no payload)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_guild_leave

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
