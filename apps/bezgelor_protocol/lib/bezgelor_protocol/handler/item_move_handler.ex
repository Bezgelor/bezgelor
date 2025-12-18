defmodule BezgelorProtocol.Handler.ItemMoveHandler do
  @moduledoc """
  Handler for ClientItemMove packets.

  Moves items between inventory locations (equipped, bags, bank).
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.CombatBroadcaster]}

  alias BezgelorProtocol.Packets.World.{ClientItemMove, ServerItemMove}
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.Inventory
  alias BezgelorData.Store
  alias BezgelorWorld.CombatBroadcaster

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientItemMove.read(reader) do
      {:ok, packet, _reader} ->
        process_move(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientItemMove: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp process_move(packet, state) do
    character = state.session_data[:character]

    if is_nil(character) do
      Logger.warning("Item move attempted without character")
      {:ok, state}
    else
      do_move(character.id, packet, state)
    end
  end

  defp do_move(character_id, packet, state) do
    from_location = ClientItemMove.location_to_atom(packet.from_location)
    to_location = ClientItemMove.location_to_atom(packet.to_location)

    Logger.info(
      "ItemMove: from #{from_location}:#{packet.from_bag_index} to #{to_location}:#{packet.to_bag_index}"
    )

    # For equipped items, bag_index is always 0 and the slot is encoded in from_bag_index
    # For bag items, bag_index is the bag number (0-3) and we need to find the item
    {from_bag, from_slot} = decode_location(from_location, packet.from_bag_index)
    {to_bag, to_slot} = decode_location(to_location, packet.to_bag_index)

    Logger.debug("  Decoded: from bag=#{from_bag} slot=#{from_slot}, to bag=#{to_bag} slot=#{to_slot}")

    case Inventory.get_item_at(character_id, from_location, from_bag, from_slot) do
      nil ->
        Logger.warning("Item not found at #{from_location}:#{from_bag}:#{from_slot}")
        {:ok, state}

      item ->
        # Check if destination has an item (swap case)
        dest_item = Inventory.get_item_at(character_id, to_location, to_bag, to_slot)

        case dest_item do
          nil ->
            # Simple move
            case Inventory.move_item(item, to_location, to_bag, to_slot) do
              {:ok, updated_item} ->
                Logger.info("Moved item #{item.item_id} to #{updated_item.container_type}:#{updated_item.bag_index}:#{updated_item.slot}")

                # Broadcast visual update if equipment changed
                if from_location == :equipped or to_location == :equipped do
                  broadcast_visual_update(character_id, state)
                end

                # ServerItemMove uses (location << 8) | slot format
                # Use the actual updated item's location/slot to match NexusForever
                response = %ServerItemMove{
                  item_guid: updated_item.id,
                  location: updated_item.container_type,
                  slot: updated_item.slot
                }
                {:reply_world_encrypted, :server_item_move, encode_packet(response), state}

              {:error, reason} ->
                Logger.warning("Failed to move item: #{inspect(reason)}")
                {:ok, state}
            end

          _existing ->
            # Swap items
            case Inventory.swap_items(item, dest_item) do
              {:ok, {updated1, _updated2}} ->
                Logger.info("Swapped items #{item.item_id} <-> #{dest_item.item_id}")

                # Broadcast visual update if equipment changed
                if from_location == :equipped or to_location == :equipped do
                  broadcast_visual_update(character_id, state)
                end

                # Send move notification for the originally dragged item
                # Use actual updated item's location/slot to match NexusForever
                response = %ServerItemMove{
                  item_guid: updated1.id,
                  location: updated1.container_type,
                  slot: updated1.slot
                }
                {:reply_world_encrypted, :server_item_move, encode_packet(response), state}

              {:error, reason} ->
                Logger.warning("Failed to swap items: #{inspect(reason)}")
                {:ok, state}
            end
        end
    end
  end

  # For equipped items, the bag_index contains the EquippedItem slot directly
  # For inventory, bag_index is the actual bag index (0-3), and we assume slot 0 for now
  # TODO: Handle proper slot decoding for bags
  defp decode_location(:equipped, bag_index) do
    # bag_index IS the equipped slot
    {0, bag_index}
  end

  defp decode_location(_location, bag_index) do
    # For bags, bag_index contains both bag and slot info
    # Format appears to be: slot in low bits, bag in high bits
    # Needs investigation - for now assume single bag
    {0, bag_index}
  end

  defp encode_packet(%ServerItemMove{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerItemMove.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  # Broadcast visual update when equipment changes
  defp broadcast_visual_update(character_id, state) do
    entity_guid = state.session_data[:entity_guid]
    character = state.session_data[:character]

    # Get all equipped items and build visuals
    equipped_items = Inventory.get_items(character_id, :equipped)
    visuals = build_visuals(equipped_items)

    # Broadcast to self (and nearby players if we had zone info)
    if entity_guid && character do
      CombatBroadcaster.broadcast_item_visual_update(entity_guid, character, visuals, [entity_guid])
    end
  end

  # Map from our internal EquippedItem slot to client ItemSlot
  # Internal slots are 0-based, client expects ItemSlot enum values
  @equipped_to_item_slot %{
    0 => 1,    # Chest -> ArmorChest
    1 => 2,    # Legs -> ArmorLegs
    2 => 3,    # Head -> ArmorHead
    3 => 4,    # Shoulder -> ArmorShoulder
    4 => 5,    # Feet -> ArmorFeet
    5 => 6,    # Hands -> ArmorHands
    6 => 7,    # WeaponTool -> WeaponTool
    15 => 43,  # Shields -> ArmorShields
    16 => 20   # WeaponPrimary -> WeaponPrimary
  }

  # Visible equipment slots (internal EquippedItem numbers)
  @visible_equipment_slots [0, 1, 2, 3, 4, 5, 16]

  defp build_visuals(equipped_items) do
    # Build map of currently equipped items by slot
    equipped_by_slot = Map.new(equipped_items, fn item -> {item.slot, item} end)

    # For each visible equipment slot, send either the item's display_id or 0 (empty)
    Enum.map(@visible_equipment_slots, fn internal_slot ->
      # Convert internal slot to client ItemSlot
      item_slot = Map.get(@equipped_to_item_slot, internal_slot, internal_slot)

      case Map.get(equipped_by_slot, internal_slot) do
        nil ->
          # Empty slot - send display_id=0 to clear the visual
          %{slot: item_slot, display_id: 0, colour_set: 0, dye_data: 0}

        item ->
          display_id = Store.get_item_display_id(item.item_id) || 0
          %{slot: item_slot, display_id: display_id, colour_set: 0, dye_data: 0}
      end
    end)
  end
end
