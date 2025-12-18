defmodule BezgelorProtocol.Packets.World.ServerHousingData do
  @moduledoc """
  Full housing plot data sent on entry.

  ## Wire Format

  ```
  plot_id          : uint32  - Plot instance ID
  character_id     : uint64  - Owner character GUID
  house_type_id    : uint32  - House type from data
  permission_level : uint8   - 0=private, 1=neighbors, 2=roommates, 3=public
  sky_id           : uint32  - Sky theme ID
  music_id         : uint32  - Music theme ID
  ground_id        : uint32  - Ground texture ID
  plot_name_len    : uint16  - Plot name string length
  plot_name        : string  - UTF-8 plot name
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :plot_id,
    :character_id,
    :house_type_id,
    :permission_level,
    :sky_id,
    :music_id,
    :ground_id,
    :plot_name
  ]

  @type permission :: :private | :neighbors | :roommates | :public
  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          character_id: non_neg_integer(),
          house_type_id: non_neg_integer(),
          permission_level: permission(),
          sky_id: non_neg_integer(),
          music_id: non_neg_integer(),
          ground_id: non_neg_integer(),
          plot_name: String.t() | nil
        }

  @impl true
  def opcode, do: :server_housing_data

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    permission_byte = permission_to_byte(packet.permission_level)
    name = packet.plot_name || ""
    name_bytes = :binary.bin_to_list(name)

    writer =
      writer
      |> PacketWriter.write_u32(packet.plot_id)
      |> PacketWriter.write_u64(packet.character_id)
      |> PacketWriter.write_u32(packet.house_type_id)
      |> PacketWriter.write_u8(permission_byte)
      |> PacketWriter.write_u32(packet.sky_id || 0)
      |> PacketWriter.write_u32(packet.music_id || 0)
      |> PacketWriter.write_u32(packet.ground_id || 0)
      |> PacketWriter.write_u16(length(name_bytes))
      |> PacketWriter.write_bytes_bits(name)

    {:ok, writer}
  end

  defp permission_to_byte(:private), do: 0
  defp permission_to_byte(:neighbors), do: 1
  defp permission_to_byte(:roommates), do: 2
  defp permission_to_byte(:public), do: 3

  @doc "Create from a HousingPlot struct."
  @spec from_plot(map()) :: t()
  def from_plot(plot) do
    %__MODULE__{
      plot_id: plot.id,
      character_id: plot.character_id,
      house_type_id: plot.house_type_id,
      permission_level: plot.permission_level,
      sky_id: plot.sky_id,
      music_id: plot.music_id,
      ground_id: plot.ground_id,
      plot_name: plot.plot_name
    }
  end
end
