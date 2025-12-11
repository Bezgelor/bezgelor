defmodule BezgelorProtocol.Packets.World.ClientInstanceTeleport do
  @moduledoc """
  Request to teleport into an instance.

  ## Wire Format
  instance_guid : binary(16)  (UUID of the instance to join)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_guid]

  @impl true
  def opcode, do: :client_instance_teleport

  @impl true
  def read(reader) do
    with {:ok, guid, reader} <- PacketReader.read_bytes(reader, 16) do
      {:ok, %__MODULE__{instance_guid: guid}, reader}
    end
  end
end
