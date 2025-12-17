defmodule BezgelorProtocol.Packets.World.ClientResurrectAtBindpoint do
  @moduledoc """
  Client request to respawn at their bindpoint.

  ## Overview

  Sent by the client when the player chooses to respawn at their
  bindpoint instead of accepting a resurrection offer or waiting.

  ## Wire Format

  Empty packet - just the opcode is sent.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_resurrect_at_bindpoint

  @impl true
  def read(reader) do
    # Empty packet - no data to read
    {:ok, %__MODULE__{}, reader}
  end
end
