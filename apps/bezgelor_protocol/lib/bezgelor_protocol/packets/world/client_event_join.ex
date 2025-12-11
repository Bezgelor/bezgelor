defmodule BezgelorProtocol.Packets.World.ClientEventJoin do
  @moduledoc """
  Request to join a public event.

  ## Wire Format
  instance_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id]

  @impl true
  def opcode, do: :client_event_join

  @impl true
  def read(reader) do
    with {:ok, instance_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{instance_id: instance_id}, reader}
    end
  end
end
