defmodule BezgelorProtocol.Packets.World.ClientMountSummon do
  @moduledoc """
  Mount summon request from client.

  ## Wire Format
  mount_id : uint32 - Mount to summon from collection
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:mount_id]

  @type t :: %__MODULE__{
          mount_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_mount_summon

  @impl true
  def read(reader) do
    with {:ok, mount_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{mount_id: mount_id}, reader}
    end
  end
end
