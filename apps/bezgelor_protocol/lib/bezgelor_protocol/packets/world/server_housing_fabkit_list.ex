defmodule BezgelorProtocol.Packets.World.ServerHousingFabkitList do
  @moduledoc """
  Full list of installed FABkits in a housing plot.

  ## Wire Format

  ```
  plot_id     : uint32  - Plot instance ID
  count       : uint8   - Number of installed FABkits (0-6)
  fabkits[]   : array   - List of FABkit entries
    fabkit_db_id  : uint32  - Database row ID
    socket_index  : uint8   - Socket index (0-5)
    fabkit_id     : uint32  - FABkit type ID from data
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:plot_id, :fabkits]

  @type fabkit_entry :: %{
          id: non_neg_integer(),
          socket_index: non_neg_integer(),
          fabkit_id: non_neg_integer()
        }

  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          fabkits: [fabkit_entry()]
        }

  @impl true
  def opcode, do: :server_housing_fabkit_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.plot_id)
      |> PacketWriter.write_byte(length(packet.fabkits))

    writer = Enum.reduce(packet.fabkits, writer, &write_fabkit_entry/2)

    {:ok, writer}
  end

  defp write_fabkit_entry(entry, writer) do
    writer
    |> PacketWriter.write_uint32(entry.id)
    |> PacketWriter.write_byte(entry.socket_index)
    |> PacketWriter.write_uint32(entry.fabkit_id)
  end

  @doc "Create from plot ID and list of HousingFabkit structs."
  @spec from_fabkit_list(non_neg_integer(), [map()]) :: t()
  def from_fabkit_list(plot_id, fabkit_list) do
    entries =
      Enum.map(fabkit_list, fn f ->
        %{id: f.id, socket_index: f.socket_index, fabkit_id: f.fabkit_id}
      end)

    %__MODULE__{plot_id: plot_id, fabkits: entries}
  end
end
