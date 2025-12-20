defmodule BezgelorProtocol.Handler.ItemMoveHandler do
  @moduledoc """
  Handler for ClientItemMove packets.

  Moves items between inventory locations (equipped, bags, bank).
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.CombatBroadcaster]}

  alias BezgelorProtocol.Packets.World.{ClientItemMove, ServerGenericError, ServerItemMove}
  alias BezgelorProtocol.{ItemSlots, PacketReader, PacketWriter}
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

    Logger.debug(
      "ItemMove: #{from_location}:#{packet.from_bag_index} -> #{to_location}:#{packet.to_bag_index}"
    )

    # For equipped items, bag_index is always 0 and the slot is encoded in from_bag_index
    # For bag items, bag_index is the bag number (0-3) and we need to find the item
    {from_bag, from_slot} = decode_location(from_location, packet.from_bag_index)
    {to_bag, to_slot} = decode_location(to_location, packet.to_bag_index)

    Logger.debug(
      "  Decoded: from bag=#{from_bag} slot=#{from_slot}, to bag=#{to_bag} slot=#{to_slot}"
    )

    case Inventory.get_item_at(character_id, from_location, from_bag, from_slot) do
      nil ->
        Logger.warning("Item not found at #{from_location}:#{from_bag}:#{from_slot}")
        send_error(ServerGenericError.item_unknown_item(), state)

      item ->
        # Check if destination has an item (swap case)
        dest_item = Inventory.get_item_at(character_id, to_location, to_bag, to_slot)

        case dest_item do
          nil ->
            # Simple move
            case Inventory.move_item(item, to_location, to_bag, to_slot) do
              {:ok, updated_item} ->
                Logger.debug(
                  "Moved item #{item.item_id} to #{updated_item.container_type}:#{updated_item.bag_index}:#{updated_item.slot}"
                )

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
                error_code = error_to_code(reason)
                send_error(error_code, state)
            end

          _existing ->
            # Swap items
            case Inventory.swap_items(item, dest_item) do
              {:ok, {updated1, _updated2}} ->
                Logger.debug("Swapped items #{item.item_id} <-> #{dest_item.item_id}")

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
                error_code = error_to_code(reason)
                send_error(error_code, state)
            end
        end
    end
  end

  # Map error reasons to GenericError codes
  defp error_to_code(:slot_occupied), do: ServerGenericError.slot_occupied()
  defp error_to_code(:inventory_full), do: ServerGenericError.item_inventory_full()
  defp error_to_code(:item_not_found), do: ServerGenericError.item_unknown_item()
  defp error_to_code(:not_valid_for_slot), do: ServerGenericError.item_not_valid_for_slot()
  defp error_to_code(_), do: ServerGenericError.item_not_valid_for_slot()

  defp send_error(error_code, state) do
    error_packet = %ServerGenericError{error: error_code}
    {:reply_world_encrypted, :server_generic_error, encode_error_packet(error_packet), state}
  end

  defp encode_error_packet(%ServerGenericError{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerGenericError.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  # WildStar uses flat inventory addressing where BagIndex is a direct slot number.
  # For equipped items: BagIndex = equipment slot (0-29 per EquippedItem enum)
  # For inventory/bank: BagIndex = flat slot index within that location
  #
  # Bezgelor stores items with (bag_index, slot) where bag_index differentiates
  # physical bags. Currently all items use bag_index=0 (single backpack model).
  # If multi-bag support is added, this function would need to query bag sizes
  # and calculate the appropriate (bag_index, slot) from the flat index.
  defp decode_location(:equipped, bag_index) do
    {0, bag_index}
  end

  defp decode_location(_location, bag_index) do
    # Flat slot index maps directly with bag_index=0 for single-bag model
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
      CombatBroadcaster.broadcast_item_visual_update(entity_guid, character, visuals, [
        entity_guid
      ])
    end
  end

  defp build_visuals(equipped_items) do
    # Build map of currently equipped items by slot
    equipped_by_slot = Map.new(equipped_items, fn item -> {item.slot, item} end)

    # For each visible equipment slot, send either the item's display_id or 0 (empty)
    Enum.map(ItemSlots.visible_equipment_slots(), fn internal_slot ->
      # Convert internal slot to client ItemSlot
      item_slot = ItemSlots.equipped_to_item_slot(internal_slot)

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
