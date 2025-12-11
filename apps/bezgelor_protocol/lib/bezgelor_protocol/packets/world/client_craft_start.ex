defmodule BezgelorProtocol.Packets.World.ClientCraftStart do
  @moduledoc """
  Client request to start a crafting session.

  ## Wire Format
  schematic_id : uint32  - Schematic to craft
  station_guid : uint64  - Crafting station entity (0 for no station)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:schematic_id, :station_guid]

  @type t :: %__MODULE__{
          schematic_id: non_neg_integer(),
          station_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_craft_start

  @impl true
  def read(reader) do
    with {:ok, schematic_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, station_guid, reader} <- PacketReader.read_uint64(reader) do
      packet = %__MODULE__{
        schematic_id: schematic_id,
        station_guid: station_guid
      }

      {:ok, packet, reader}
    end
  end
end
