defmodule BezgelorProtocol.Packets.World.ClientCraftCancel do
  @moduledoc """
  Client request to cancel the current craft session.

  ## Wire Format
  No additional data - cancels active session.
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_craft_cancel

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
