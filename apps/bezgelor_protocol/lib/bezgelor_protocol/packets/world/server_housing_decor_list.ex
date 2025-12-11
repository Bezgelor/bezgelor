defmodule BezgelorProtocol.Packets.World.ServerHousingDecorList do
  @moduledoc """
  Full list of decor items in a housing plot.

  ## Wire Format

  ```
  plot_id     : uint32  - Plot instance ID
  count       : uint16  - Number of decor items
  decor[]     : array   - List of decor entries
    decor_db_id : uint32  - Database row ID
    decor_id    : uint32  - Decor type ID from data
    pos_x       : float32 - X position
    pos_y       : float32 - Y position
    pos_z       : float32 - Z position
    rot_pitch   : float32 - Pitch rotation (degrees)
    rot_yaw     : float32 - Yaw rotation (degrees)
    rot_roll    : float32 - Roll rotation (degrees)
    scale       : float32 - Scale factor
    is_exterior : uint8   - 1 if exterior, 0 if interior
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:plot_id, :decor]

  @type decor_entry :: %{
          id: non_neg_integer(),
          decor_id: non_neg_integer(),
          pos_x: float(),
          pos_y: float(),
          pos_z: float(),
          rot_pitch: float(),
          rot_yaw: float(),
          rot_roll: float(),
          scale: float(),
          is_exterior: boolean()
        }

  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          decor: [decor_entry()]
        }

  @impl true
  def opcode, do: :server_housing_decor_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.plot_id)
      |> PacketWriter.write_uint16(length(packet.decor))

    writer = Enum.reduce(packet.decor, writer, &write_decor_entry/2)

    {:ok, writer}
  end

  defp write_decor_entry(entry, writer) do
    exterior_byte = if entry.is_exterior, do: 1, else: 0

    writer
    |> PacketWriter.write_uint32(entry.id)
    |> PacketWriter.write_uint32(entry.decor_id)
    |> PacketWriter.write_float32(entry.pos_x)
    |> PacketWriter.write_float32(entry.pos_y)
    |> PacketWriter.write_float32(entry.pos_z)
    |> PacketWriter.write_float32(entry.rot_pitch)
    |> PacketWriter.write_float32(entry.rot_yaw)
    |> PacketWriter.write_float32(entry.rot_roll)
    |> PacketWriter.write_float32(entry.scale)
    |> PacketWriter.write_byte(exterior_byte)
  end

  @doc "Create from plot ID and list of HousingDecor structs."
  @spec from_decor_list(non_neg_integer(), [map()]) :: t()
  def from_decor_list(plot_id, decor_list) do
    entries =
      Enum.map(decor_list, fn d ->
        %{
          id: d.id,
          decor_id: d.decor_id,
          pos_x: d.pos_x,
          pos_y: d.pos_y,
          pos_z: d.pos_z,
          rot_pitch: d.rot_pitch,
          rot_yaw: d.rot_yaw,
          rot_roll: d.rot_roll,
          scale: d.scale,
          is_exterior: d.is_exterior
        }
      end)

    %__MODULE__{plot_id: plot_id, decor: entries}
  end
end
