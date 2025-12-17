defmodule BezgelorProtocol.Packets.World.ServerItemVisualUpdate do
  @moduledoc """
  Server notification of equipment visual changes.

  Sent when a player equips or unequips gear to update their visible appearance
  for nearby players.

  ## Wire Format (from NexusForever)
  player_guid   : uint32
  visuals_count : uint8
  visuals[]     : ItemVisual (bit-packed)
    - slot        : 7 bits (ItemSlot enum)
    - display_id  : 15 bits
    - colour_set  : 14 bits
    - dye_data    : int32 (signed, byte-aligned after bits)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:player_guid, :visuals]

  @type item_visual :: %{
          slot: non_neg_integer(),
          display_id: non_neg_integer(),
          colour_set: non_neg_integer(),
          dye_data: integer()
        }

  @type t :: %__MODULE__{
          player_guid: non_neg_integer(),
          visuals: [item_visual()]
        }

  @impl true
  def opcode, do: :server_item_visual_update

  @doc "Create a new ServerItemVisualUpdate packet."
  @spec new(non_neg_integer(), [item_visual()]) :: t()
  def new(player_guid, visuals) do
    %__MODULE__{
      player_guid: player_guid,
      visuals: visuals
    }
  end

  @doc "Create an item visual entry."
  @spec visual(non_neg_integer(), non_neg_integer(), non_neg_integer(), integer()) :: item_visual()
  def visual(slot, display_id, colour_set \\ 0, dye_data \\ 0) do
    %{
      slot: slot,
      display_id: display_id,
      colour_set: colour_set,
      dye_data: dye_data
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.player_guid)
      |> PacketWriter.write_byte(length(packet.visuals))

    # Write each visual (bit-packed fields)
    writer =
      Enum.reduce(packet.visuals, writer, fn visual, w ->
        w
        |> PacketWriter.write_bits(visual.slot, 7)
        |> PacketWriter.write_bits(visual.display_id, 15)
        |> PacketWriter.write_bits(visual.colour_set, 14)
        |> PacketWriter.flush_bits()
        |> PacketWriter.write_int32(visual.dye_data)
      end)

    {:ok, writer}
  end
end
