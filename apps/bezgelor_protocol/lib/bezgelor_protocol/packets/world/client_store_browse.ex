defmodule BezgelorProtocol.Packets.World.ClientStoreBrowse do
  @moduledoc """
  Client request to browse store catalog.

  ## Wire Format
  category_id : uint32 (0 = all categories)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:category_id]

  @impl true
  def opcode, do: :client_store_browse

  @impl true
  def read(reader) do
    {category_id, reader} = PacketReader.read_uint32(reader)

    packet = %__MODULE__{
      category_id: category_id
    }

    {:ok, packet, reader}
  end
end
