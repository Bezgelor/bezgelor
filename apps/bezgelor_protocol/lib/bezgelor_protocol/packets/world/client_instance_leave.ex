defmodule BezgelorProtocol.Packets.World.ClientInstanceLeave do
  @moduledoc """
  Request to leave the current instance.

  ## Wire Format
  teleport_out : uint8  (0=stay at entrance, 1=teleport to previous location)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct teleport_out: true

  @impl true
  def opcode, do: :client_instance_leave

  @impl true
  def read(reader) do
    with {:ok, teleport_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok, %__MODULE__{teleport_out: teleport_byte == 1}, reader}
    end
  end
end
