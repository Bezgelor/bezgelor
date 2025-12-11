defmodule BezgelorProtocol.Packets.World.ClientGatherStart do
  @moduledoc """
  Client request to start gathering from a node.

  ## Wire Format
  node_guid : uint64  - GUID of the gathering node entity
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:node_guid]

  @type t :: %__MODULE__{
          node_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_gather_start

  @impl true
  def read(reader) do
    with {:ok, node_guid, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{node_guid: node_guid}, reader}
    end
  end
end
