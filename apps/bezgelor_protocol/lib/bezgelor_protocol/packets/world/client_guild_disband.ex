defmodule BezgelorProtocol.Packets.World.ClientGuildDisband do
  @moduledoc """
  Disband the guild (guild master only).

  ## Wire Format
  (empty - no payload)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_guild_disband

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
