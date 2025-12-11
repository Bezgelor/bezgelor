defmodule BezgelorProtocol.Packets.World.ServerHousingNeighborList do
  @moduledoc """
  List of neighbors for a housing plot.

  ## Wire Format

  ```
  plot_id      : uint32  - Plot instance ID
  count        : uint16  - Number of neighbors
  neighbors[]  : array   - List of neighbor entries
    character_id : uint64  - Neighbor character GUID
    is_roommate  : uint8   - 1 if roommate, 0 if regular neighbor
    name_len     : uint16  - Character name length
    name         : string  - UTF-8 character name
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:plot_id, :neighbors]

  @type neighbor_entry :: %{
          character_id: non_neg_integer(),
          is_roommate: boolean(),
          name: String.t()
        }

  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          neighbors: [neighbor_entry()]
        }

  @impl true
  def opcode, do: :server_housing_neighbor_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.plot_id)
      |> PacketWriter.write_uint16(length(packet.neighbors))

    writer = Enum.reduce(packet.neighbors, writer, &write_neighbor_entry/2)

    {:ok, writer}
  end

  defp write_neighbor_entry(entry, writer) do
    roommate_byte = if entry.is_roommate, do: 1, else: 0
    name = entry.name || ""
    name_bytes = :binary.bin_to_list(name)

    writer
    |> PacketWriter.write_uint64(entry.character_id)
    |> PacketWriter.write_byte(roommate_byte)
    |> PacketWriter.write_uint16(length(name_bytes))
    |> PacketWriter.write_bytes(name)
  end

  @doc "Create from plot ID and list of HousingNeighbor structs with preloaded character."
  @spec from_neighbor_list(non_neg_integer(), [map()]) :: t()
  def from_neighbor_list(plot_id, neighbor_list) do
    entries =
      Enum.map(neighbor_list, fn n ->
        character_name = if n.character, do: n.character.name, else: "Unknown"

        %{
          character_id: n.character_id,
          is_roommate: n.is_roommate,
          name: character_name
        }
      end)

    %__MODULE__{plot_id: plot_id, neighbors: entries}
  end
end
