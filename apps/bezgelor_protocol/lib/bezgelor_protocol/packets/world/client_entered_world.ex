defmodule BezgelorProtocol.Packets.World.ClientEnteredWorld do
  @moduledoc """
  Client notification that world has loaded.

  ## Overview

  Sent by client after receiving ServerWorldEnter and finishing
  world asset loading. Server should then spawn the player entity.

  ## Wire Format

  This is an acknowledgment packet with no payload.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_entered_world

  @impl true
  def read(reader) do
    # No payload - just an acknowledgment
    {:ok, %__MODULE__{}, reader}
  end
end
