defmodule BezgelorProtocol.Packets.World.ServerCraftSession do
  @moduledoc """
  Crafting session state update.

  ## Wire Format
  schematic_id    : uint32
  cursor_x        : float32
  cursor_y        : float32
  overcharge_level: uint8
  additive_count  : uint8
  additives[]     : additive_data (repeated)

  additive_data:
    item_id  : uint32
    quantity : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:schematic_id, :cursor_x, :cursor_y, :overcharge_level, additives: []]

  @type additive :: %{item_id: non_neg_integer(), quantity: non_neg_integer()}

  @type t :: %__MODULE__{
          schematic_id: non_neg_integer(),
          cursor_x: float(),
          cursor_y: float(),
          overcharge_level: non_neg_integer(),
          additives: [additive()]
        }

  @impl true
  def opcode, do: :server_craft_session

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.schematic_id)
      |> PacketWriter.write_f32(packet.cursor_x)
      |> PacketWriter.write_f32(packet.cursor_y)
      |> PacketWriter.write_u8(packet.overcharge_level)
      |> PacketWriter.write_u8(length(packet.additives))

    writer =
      Enum.reduce(packet.additives, writer, fn add, w ->
        w
        |> PacketWriter.write_u32(add.item_id)
        |> PacketWriter.write_u16(add.quantity)
      end)

    {:ok, writer}
  end
end
