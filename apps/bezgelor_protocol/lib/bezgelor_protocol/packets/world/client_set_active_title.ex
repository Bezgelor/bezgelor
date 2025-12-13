defmodule BezgelorProtocol.Packets.World.ClientSetActiveTitle do
  @moduledoc """
  Client request to change active displayed title.

  ## Wire Format
  title_id : uint32 (0 to clear)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:title_id]

  @impl true
  def opcode, do: :client_set_active_title

  @impl true
  def read(reader) do
    {:ok, title_id, reader} = PacketReader.read_uint32(reader)

    packet = %__MODULE__{
      title_id: if(title_id == 0, do: nil, else: title_id)
    }

    {:ok, packet, reader}
  end
end
