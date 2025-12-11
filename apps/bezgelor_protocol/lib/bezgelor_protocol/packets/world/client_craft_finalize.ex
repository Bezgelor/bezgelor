defmodule BezgelorProtocol.Packets.World.ClientCraftFinalize do
  @moduledoc """
  Client request to finalize the current craft.

  ## Wire Format
  No additional data - uses current session state.
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_craft_finalize

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
