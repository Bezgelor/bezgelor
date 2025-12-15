defmodule BezgelorProtocol.Packets.World.ServerCinematicComplete do
  @moduledoc """
  Notify client that a cinematic has completed.

  This is an empty packet - the presence of it signals completion.

  ## Wire Format

  Empty packet (no fields)

  Opcode: 0x0210
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{}

  defstruct []

  @impl true
  def opcode, do: :server_cinematic_complete

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{}, writer) do
    {:ok, writer}
  end
end
