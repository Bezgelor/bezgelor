defmodule BezgelorProtocol.Packets.World.ServerPlayerEnteredWorld do
  @moduledoc """
  Server packet sent to dismiss the loading screen.

  Sent in response to ClientEnteredWorld after the client has finished loading.
  This is an empty packet - just the opcode signals the client to exit the loading screen.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_player_entered_world

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{}, writer) do
    # Empty packet - no data to write
    {:ok, writer}
  end
end
