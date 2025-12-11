defmodule BezgelorProtocol.Packets.World.ClientMythicKeystoneList do
  @moduledoc """
  Request list of player's keystones.

  ## Wire Format
  (empty - requests all keystones for the character)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_mythic_keystone_list

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
