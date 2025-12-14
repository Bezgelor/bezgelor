defmodule BezgelorProtocol.Packets.World.ServerStoreFinalise do
  @moduledoc """
  Server packet indicating store catalog is complete.

  ## Overview

  Sent after all store categories and offers have been sent.
  Signals to the client that it can now display the character select screen.

  ## Packet Structure

  Empty packet (opcode only).
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_store_finalise

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{}, writer) do
    {:ok, writer}
  end
end
