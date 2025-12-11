defmodule BezgelorProtocol.Packets.World.ClientEventLeave do
  @moduledoc """
  Request to leave a public event.

  ## Wire Format
  instance_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id]

  @impl true
  def opcode, do: :client_event_leave

  @impl true
  def read(reader) do
    with {:ok, instance_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{instance_id: instance_id}, reader}
    end
  end
end
