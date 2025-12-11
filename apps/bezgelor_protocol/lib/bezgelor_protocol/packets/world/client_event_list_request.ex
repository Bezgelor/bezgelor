defmodule BezgelorProtocol.Packets.World.ClientEventListRequest do
  @moduledoc """
  Request list of active events in zone.

  ## Wire Format
  (empty packet - zone derived from player location)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_event_list_request

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
