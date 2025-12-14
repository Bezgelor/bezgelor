defmodule BezgelorProtocol.Packets.World.ServerHousingNeighbors do
  @moduledoc """
  Server packet with housing neighbors list.

  ## Packet Structure

  ```
  count : uint32 - Number of neighbors (0 for no housing)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_housing_neighbors

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{}, writer) do
    # Empty neighbors list
    writer =
      writer
      |> PacketWriter.write_bits(0, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
