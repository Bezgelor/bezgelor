defmodule BezgelorProtocol.Packets.World.ClientMailGetInbox do
  @moduledoc """
  Request inbox contents.

  ## Wire Format
  (empty - no payload)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_mail_get_inbox

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
