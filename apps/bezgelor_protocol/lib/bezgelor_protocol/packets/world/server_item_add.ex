defmodule BezgelorProtocol.Packets.World.ServerItemAdd do
  @moduledoc """
  New item added to inventory.

  ## Wire Format (from NexusForever)

  Item structure:
    guid              : uint64
    unknown0          : uint64
    item_id           : uint32 (18 bits)
    location          : 9-bit enum + uint32 bag_index
    stack_count       : uint32
    charges           : uint32
    random_circuit_data : uint64
    random_glyph_data : uint32
    threshold_data    : uint64
    durability        : float32
    unknown44         : uint32
    unknown48         : uint8
    dye_data          : uint32
    dynamic_flags     : uint32
    expiration_time_left : uint32
    unknown58[2]      : array of {3-bit, uint32, uint32}
    unknown70         : uint32 (18 bits)
    microchips_count  : 3 bits
    microchips[]      : uint32 * count
    glyphs_count      : 4 bits
    glyphs[]          : uint32 * count
    unknown88_count   : 6 bits
    unknown88[]       : {14-bit, uint64} * count
    effective_item_level : uint32

  InventoryItem wrapper:
    item              : Item (above)
    reason            : 6-bit enum (ItemUpdateReason)

  ## InventoryLocation enum values
  - 0: Equipped
  - 1: Inventory (bags)
  - 2: Bank
  - 5: BuyBack
  - 6: Ability
  - 7: SupplySatchel
  """
  @behaviour BezgelorProtocol.Packet.Writable

  import Bitwise

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :guid,
    :item_id,
    :location,
    :bag_index,
    :stack_count,
    :durability,
    # Optional fields with defaults
    charges: 0,
    random_circuit_data: 0,
    random_glyph_data: 0,
    threshold_data: 0,
    dye_data: 0,
    dynamic_flags: 0,
    expiration_time_left: 0,
    effective_item_level: 0,
    microchips: [],
    glyphs: [],
    reason: :no_reason
  ]

  # InventoryLocation enum (9 bits)
  @location_equipped 0
  @location_inventory 1
  @location_bank 2

  # ItemUpdateReason enum (6 bits)
  @reason_no_reason 0

  @impl true
  def opcode, do: :server_item_add

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Generate a unique item guid if not provided
    guid = packet.guid || generate_item_guid(packet.bag_index, packet.location)

    writer =
      writer
      # Item guid (unique instance ID)
      |> PacketWriter.write_uint64(guid)
      # Unknown0 (always 0)
      |> PacketWriter.write_uint64(0)
      # Item ID (18 bits, write as padded uint32)
      |> PacketWriter.write_bits(packet.item_id, 18)
      # Location (9-bit enum)
      |> PacketWriter.write_bits(location_to_int(packet.location), 9)
      # Bag index (uint32)
      |> PacketWriter.write_uint32(packet.bag_index || 0)
      # Stack count
      |> PacketWriter.write_uint32(packet.stack_count || 1)
      # Charges
      |> PacketWriter.write_uint32(packet.charges || 0)
      # Random circuit data
      |> PacketWriter.write_uint64(packet.random_circuit_data || 0)
      # Random glyph data
      |> PacketWriter.write_uint32(packet.random_glyph_data || 0)
      # Threshold data
      |> PacketWriter.write_uint64(packet.threshold_data || 0)
      # Durability (float, 0.0 to 1.0)
      |> PacketWriter.write_float32(normalize_durability(packet.durability))
      # Unknown44
      |> PacketWriter.write_uint32(0)
      # Unknown48
      |> PacketWriter.write_byte(0)
      # Dye data
      |> PacketWriter.write_uint32(packet.dye_data || 0)
      # Dynamic flags
      |> PacketWriter.write_uint32(packet.dynamic_flags || 0)
      # Expiration time left
      |> PacketWriter.write_uint32(packet.expiration_time_left || 0)

    # Unknown58 array (2 elements, each with 3-bit + uint32 + uint32)
    writer =
      writer
      |> write_unknown58_entry()
      |> write_unknown58_entry()

    # Unknown70 (18 bits)
    writer = PacketWriter.write_bits(writer, 0, 18)

    # Microchips (3-bit count + uint32[])
    microchips = packet.microchips || []
    writer = PacketWriter.write_bits(writer, length(microchips), 3)
    writer = Enum.reduce(microchips, writer, &PacketWriter.write_uint32(&2, &1))

    # Glyphs (4-bit count + uint32[])
    glyphs = packet.glyphs || []
    writer = PacketWriter.write_bits(writer, length(glyphs), 4)
    writer = Enum.reduce(glyphs, writer, &PacketWriter.write_uint32(&2, &1))

    # Unknown88 (6-bit count + {14-bit, uint64}[])
    writer = PacketWriter.write_bits(writer, 0, 6)

    # Effective item level
    writer = PacketWriter.write_uint32(writer, packet.effective_item_level || 0)

    # ItemUpdateReason (6 bits)
    writer = PacketWriter.write_bits(writer, reason_to_int(packet.reason), 6)

    {:ok, writer}
  end

  # Write an Unknown58 entry (3-bit + uint32 + uint32)
  defp write_unknown58_entry(writer) do
    writer
    |> PacketWriter.write_bits(0, 3)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
  end

  # Generate a unique item guid from location and slot
  defp generate_item_guid(bag_index, location) do
    # Simple GUID generation: combine location type with bag index
    # Real implementation would use database item instance IDs
    location_int = location_to_int(location)
    (location_int <<< 32) ||| (bag_index || 0)
  end

  # Convert durability (0-100 or 0.0-1.0) to float 0.0-1.0
  defp normalize_durability(nil), do: 1.0
  defp normalize_durability(d) when is_float(d) and d <= 1.0, do: d
  defp normalize_durability(d) when is_integer(d), do: d / 100.0
  defp normalize_durability(d) when is_float(d), do: d / 100.0

  defp location_to_int(:equipped), do: @location_equipped
  defp location_to_int(:inventory), do: @location_inventory
  defp location_to_int(:bag), do: @location_inventory
  defp location_to_int(:bank), do: @location_bank
  defp location_to_int(loc) when is_integer(loc), do: loc
  defp location_to_int(_), do: @location_inventory

  defp reason_to_int(:no_reason), do: @reason_no_reason
  defp reason_to_int(reason) when is_integer(reason), do: reason
  defp reason_to_int(_), do: @reason_no_reason
end
