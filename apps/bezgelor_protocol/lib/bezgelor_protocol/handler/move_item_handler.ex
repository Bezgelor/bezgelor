defmodule BezgelorProtocol.Handler.MoveItemHandler do
  @moduledoc """
  Handles ClientMoveItem packets.

  ## Overview

  Processes item movement requests between inventory locations:
  - Equipped slots
  - Bag slots
  - Bank slots
  - Trade slots

  ## Flow

  1. Parse ClientMoveItem packet
  2. Validate player is in world
  3. Get item at source location
  4. Check destination validity
  5. Move or swap items
  6. Send response packets
  7. Broadcast visual update if equipment changed
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.CombatBroadcaster, BezgelorWorld.ZoneManager]}

  alias BezgelorDb.Inventory
  alias BezgelorData.Store
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorProtocol.Packets.World.{ClientMoveItem, ServerItemMove, ServerItemSwap}
  alias BezgelorWorld.CombatBroadcaster

  require Logger

  @impl true
  def handle(payload, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Move item received before player entered world")
      {:ok, state}
    else
      reader = PacketReader.new(payload)

      case ClientMoveItem.read(reader) do
        {:ok, packet, _reader} ->
          handle_move_item(packet, state)

        {:error, reason} ->
          Logger.warning("Failed to parse ClientMoveItem: #{inspect(reason)}")
          {:ok, state}
      end
    end
  end

  defp handle_move_item(packet, state) do
    character_id = state.session_data[:character].id

    Logger.debug(
      "Move item: #{packet.src_container}/#{packet.src_bag_index}/#{packet.src_slot} -> " <>
        "#{packet.dst_container}/#{packet.dst_bag_index}/#{packet.dst_slot}"
    )

    # Get item at source location
    case Inventory.get_item_at(
           character_id,
           packet.src_container,
           packet.src_bag_index,
           packet.src_slot
         ) do
      nil ->
        Logger.warning("Move item: no item at source location")
        {:ok, state}

      source_item ->
        # Check if destination has an item (for swap)
        dest_item =
          Inventory.get_item_at(
            character_id,
            packet.dst_container,
            packet.dst_bag_index,
            packet.dst_slot
          )

        if dest_item do
          handle_swap(source_item, dest_item, packet, state)
        else
          handle_move(source_item, packet, state)
        end
    end
  end

  defp handle_move(source_item, packet, state) do
    case Inventory.move_item(
           source_item,
           packet.dst_container,
           packet.dst_bag_index,
           packet.dst_slot
         ) do
      {:ok, updated_item} ->
        Logger.info("Item moved: #{source_item.item_id} to #{packet.dst_container}/#{packet.dst_bag_index}/#{packet.dst_slot}")

        # Send move confirmation
        state = send_item_move(updated_item, state)

        # Broadcast visual update if equipping/unequipping
        state = maybe_broadcast_visual_update(packet, state)

        {:ok, state}

      {:error, :slot_occupied} ->
        Logger.warning("Move item: destination slot occupied (race condition)")
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Move item failed: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_swap(source_item, dest_item, packet, state) do
    case Inventory.swap_items(source_item, dest_item) do
      {:ok, {updated_source, updated_dest}} ->
        Logger.info("Items swapped: #{source_item.item_id} <-> #{dest_item.item_id}")

        # Send swap confirmation
        state = send_item_swap(updated_source, updated_dest, state)

        # Broadcast visual update if equipping/unequipping
        state = maybe_broadcast_visual_update(packet, state)

        {:ok, state}

      {:error, reason} ->
        Logger.warning("Swap items failed: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp send_item_move(item, state) do
    packet = %ServerItemMove{
      item_guid: item.id,
      location: item.container_type,
      slot: item.slot
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerItemMove.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Queue packet for sending
    packets = Map.get(state, :pending_packets, [])
    %{state | pending_packets: [{:server_item_move, packet_data} | packets]}
  end

  defp send_item_swap(item1, item2, state) do
    packet = %ServerItemSwap{
      item1_guid: item1.id,
      item1_location: item1.container_type,
      item1_bag_index: item1.bag_index,
      item1_slot: item1.slot,
      item2_guid: item2.id,
      item2_location: item2.container_type,
      item2_bag_index: item2.bag_index,
      item2_slot: item2.slot
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerItemSwap.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Queue packet for sending
    packets = Map.get(state, :pending_packets, [])
    %{state | pending_packets: [{:server_item_swap, packet_data} | packets]}
  end

  defp maybe_broadcast_visual_update(packet, state) do
    # Check if source or destination is an equipped slot
    if packet.src_container == :equipped or packet.dst_container == :equipped do
      broadcast_visual_update(state)
    else
      state
    end
  end

  defp broadcast_visual_update(state) do
    character = state.session_data[:character]
    character_id = character.id
    entity_guid = state.session_data[:entity_guid]
    zone_id = state.session_data[:zone_id]

    # Get all equipped items and build visuals
    equipped_items = Inventory.get_items(character_id, :equipped)
    visuals = build_visuals(equipped_items)

    # Get nearby players from zone (include self for immediate feedback)
    recipient_guids = get_nearby_players(zone_id, entity_guid)

    if recipient_guids != [] do
      CombatBroadcaster.broadcast_item_visual_update(entity_guid, character, visuals, recipient_guids)
    end

    state
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

  defp get_nearby_players(zone_id, player_guid) do
    # For now, just return the player themselves for immediate feedback
    # Full implementation would query ZoneInstance for nearby players
    if zone_id do
      [player_guid]
    else
      []
    end
  end
end
