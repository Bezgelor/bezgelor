defmodule BezgelorProtocol.Packets.World.ClientCancelCast do
  @moduledoc """
  Cancel current spell cast request.

  ## Overview

  Sent when a player wants to cancel their current spell cast.
  Empty payload - simply indicates cancellation request.

  ## Wire Format

  ```
  (empty payload)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_cancel_cast

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
