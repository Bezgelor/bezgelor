defmodule BezgelorProtocol.Packets.World.ServerEntityVisualUpdate do
  @moduledoc """
  Server notification of entity visual changes (equipment appearance).

  Sent when a player equips or unequips gear to update their visible appearance.

  ## Wire Format (from NexusForever)
  unit_id          : uint32
  race             : 5 bits
  sex              : 2 bits
  creature_id      : 18 bits
  display_info     : 17 bits
  outfit_info      : 15 bits
  item_color_set_id: uint32
  unknown6         : bool (1 bit)
  visuals_count    : uint32
  visuals[]        : ItemVisual (bit-packed)
    - slot         : 7 bits (ItemSlot enum)
    - display_id   : 15 bits
    - colour_set   : 14 bits
    - dye_data     : int32 (byte-aligned after bits)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct unit_id: 0,
            race: 0,
            sex: 0,
            creature_id: 0,
            display_info: 0,
            outfit_info: 0,
            item_color_set_id: 0,
            visuals: []

  @type item_visual :: %{
          slot: non_neg_integer(),
          display_id: non_neg_integer(),
          colour_set: non_neg_integer(),
          dye_data: integer()
        }

  @type t :: %__MODULE__{
          unit_id: non_neg_integer(),
          race: non_neg_integer(),
          sex: non_neg_integer(),
          creature_id: non_neg_integer(),
          display_info: non_neg_integer(),
          outfit_info: non_neg_integer(),
          item_color_set_id: non_neg_integer(),
          visuals: [item_visual()]
        }

  @impl true
  def opcode, do: :server_entity_visual_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    require Logger

    Logger.info(
      "ServerEntityVisualUpdate: unit_id=#{packet.unit_id} race=#{packet.race} sex=#{packet.sex} " <>
        "visuals_count=#{length(packet.visuals)}"
    )

    for visual <- packet.visuals do
      Logger.info("  Visual: slot=#{visual.slot} display_id=#{visual.display_id}")
    end

    # NexusForever writes all fields as continuous bits (no flush between fields)
    writer =
      writer
      |> PacketWriter.write_bits(packet.unit_id, 32)
      |> PacketWriter.write_bits(packet.race, 5)
      |> PacketWriter.write_bits(packet.sex, 2)
      |> PacketWriter.write_bits(packet.creature_id, 18)
      |> PacketWriter.write_bits(packet.display_info, 17)
      |> PacketWriter.write_bits(packet.outfit_info, 15)
      |> PacketWriter.write_bits(packet.item_color_set_id, 32)
      # Unknown6 bool (1 bit)
      |> PacketWriter.write_bits(0, 1)
      # Visuals count (32 bits)
      |> PacketWriter.write_bits(length(packet.visuals), 32)

    # Write each visual (bit-packed fields, then DyeData as full int32)
    writer =
      Enum.reduce(packet.visuals, writer, fn visual, w ->
        w
        |> PacketWriter.write_bits(visual.slot, 7)
        |> PacketWriter.write_bits(visual.display_id, 15)
        |> PacketWriter.write_bits(visual.colour_set, 14)
        |> PacketWriter.write_bits(visual.dye_data, 32)
      end)

    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end
end
