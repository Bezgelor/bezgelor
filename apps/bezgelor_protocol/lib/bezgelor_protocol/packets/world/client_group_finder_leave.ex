defmodule BezgelorProtocol.Packets.World.ClientGroupFinderLeave do
  @moduledoc """
  Request to leave the group finder queue.

  ## Wire Format
  (empty - no parameters needed)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_group_finder_leave

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
