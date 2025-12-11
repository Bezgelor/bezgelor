defmodule BezgelorProtocol.Packets.World.ClientGetTitles do
  @moduledoc """
  Client request for title list.

  ## Wire Format
  (empty - no payload)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_get_titles

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
