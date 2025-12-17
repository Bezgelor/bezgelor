# Inventory & Gear System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Created:** 2025-12-16
**Goal:** Make gear slots functional - players can equip items, see them visually, get stat bonuses, buy/sell from vendors, and use bank storage.

**Problem:** Gear slots show nothing because:
1. No handler for `ClientMoveItem` - equip requests silently dropped
2. No `ServerItemVisualUpdate` packet - gear changes not broadcast
3. No starter gear - characters spawn with empty inventory
4. Gear stats not wired to combat calculations

**Tech Stack:** Elixir/OTP, Ecto, ETS for game data, binary protocol packets with bit-packing.

---

## Implementation Order

1. **Phase 1: Core Item Movement (Tasks 1-6)** - Wire up item equipping with visual feedback
2. **Phase 2: Starter Gear (Tasks 7-10)** - Class-based equipment on character creation
3. **Phase 3: Stats Integration (Tasks 11-13)** - Equipped gear affects combat
4. **Phase 4: Vendor System (Tasks 14-19)** - Buy/sell from NPCs
5. **Phase 5: Bank Storage (Tasks 20-22)** - Personal bank access
6. **Phase 6: GM Commands (Tasks 23-24)** - /additem for testing

---

## Phase 1: Core Item Movement

### Task 1: Create MoveItemHandler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/move_item_handler.ex`
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_registry.ex`

**Implementation:**
```elixir
defmodule BezgelorProtocol.Handler.MoveItemHandler do
  @behaviour BezgelorProtocol.Handler

  alias BezgelorDb.Inventory
  alias BezgelorProtocol.Packets.World.{ClientMoveItem, ServerItemMove, ServerItemSwap}

  @impl true
  def handle(payload, state) do
    with {:ok, packet, _} <- ClientMoveItem.read(PacketReader.new(payload)),
         character_id <- state.session_data[:character].id,
         {:ok, result} <- Inventory.move_item(character_id, packet.from, packet.to) do

      case result do
        {:moved, item} ->
          # Send ServerItemMove to confirm
          send_item_move(item, packet.to, state)

        {:swapped, item1, item2} ->
          # Send ServerItemSwap for both items
          send_item_swap(item1, item2, state)
      end

      # If destination is equipped slot, broadcast visual update
      if packet.to.location == :equipped do
        broadcast_visual_update(character_id, state)
      end

      {:ok, state}
    end
  end
end
```

**Register in PacketRegistry:**
```elixir
client_move_item: Handler.MoveItemHandler,
```

---

### Task 2: Create ServerItemMove Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_item_move.ex`
- Create: `apps/bezgelor_protocol/test/packets/world/server_item_move_test.exs`

**Wire Format (from NexusForever):**
```
ItemDragDrop:
  guid      : uint64  - item GUID
  drag_drop : uint64  - encoded (location << 8 | bag_index)
```

**Implementation:**
```elixir
defmodule BezgelorProtocol.Packets.World.ServerItemMove do
  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [:item_guid, :location, :bag_index]

  @impl true
  def opcode, do: :server_item_move

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    drag_drop = encode_drag_drop(packet.location, packet.bag_index)

    writer
    |> PacketWriter.write_uint64(packet.item_guid)
    |> PacketWriter.write_uint64(drag_drop)
    |> then(&{:ok, &1})
  end

  defp encode_drag_drop(location, bag_index) do
    location_int = location_to_int(location)
    (location_int <<< 8) ||| bag_index
  end

  defp location_to_int(:equipped), do: 0
  defp location_to_int(:inventory), do: 1
  defp location_to_int(:player_bank), do: 2
end
```

---

### Task 3: Create ServerItemSwap Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_item_swap.ex`
- Create: `apps/bezgelor_protocol/test/packets/world/server_item_swap_test.exs`

**Wire Format:**
```
To:   ItemDragDrop (item being moved)
From: ItemDragDrop (item at destination that's being displaced)
```

---

### Task 4: Create ServerItemVisualUpdate Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_item_visual_update.ex`
- Create: `apps/bezgelor_protocol/test/packets/world/server_item_visual_update_test.exs`

**Wire Format (from NexusForever):**
```
player_guid   : uint32
visuals_count : variable
visuals[]     : ItemVisual
  - slot        : 7 bits (ItemSlot enum)
  - display_id  : 15 bits
  - colour_set  : 14 bits
  - dye_data    : int32 (signed)
```

**Implementation:**
```elixir
defmodule BezgelorProtocol.Packets.World.ServerItemVisualUpdate do
  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [:player_guid, :visuals]

  @type item_visual :: {slot :: integer(), display_id :: integer(), colour_set :: integer(), dye_data :: integer()}

  @impl true
  def opcode, do: :server_item_visual_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, packet.player_guid)

    # Write count then each visual
    Enum.reduce(packet.visuals, writer, fn {slot, display_id, colour_set, dye_data}, w ->
      w
      |> PacketWriter.write_bits(slot, 7)
      |> PacketWriter.write_bits(display_id, 15)
      |> PacketWriter.write_bits(colour_set, 14)
      |> PacketWriter.write_signed_int32(dye_data)
    end)
    |> then(&{:ok, &1})
  end
end
```

---

### Task 5: Add Equip Validation to Inventory

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`
- Create: `apps/bezgelor_db/test/inventory_equip_test.exs`

**Add functions:**
```elixir
@doc """
Check if an item can be equipped in a specific slot.
Uses EquippedSlotFlags bitmask from ItemSlotEntry.
"""
@spec can_equip_in_slot?(integer(), integer()) :: boolean()
def can_equip_in_slot?(item_id, slot) do
  case BezgelorData.Store.get_item(item_id) do
    nil -> false
    item ->
      slot_entry = BezgelorData.Store.get_item_slot_entry(item.item_slot_id)
      slot_entry && (slot_entry.equipped_slot_flags &&& (1 <<< slot)) != 0
  end
end

@doc """
Move an item, validating equip compatibility if destination is equipped.
"""
@spec move_item(integer(), item_location(), item_location()) ::
  {:ok, {:moved, map()} | {:swapped, map(), map()}} | {:error, atom()}
def move_item(character_id, from, to) do
  with {:ok, item} <- get_item_at(character_id, from.location, from.bag_index),
       :ok <- validate_destination(item, to) do

    case get_item_at(character_id, to.location, to.bag_index) do
      {:ok, dest_item} ->
        # Swap items
        swap_items(character_id, item, dest_item, from, to)

      {:error, :not_found} ->
        # Simple move
        update_item_location(item, to)
    end
  end
end

defp validate_destination(item, %{location: :equipped, bag_index: slot}) do
  if can_equip_in_slot?(item.item_id, slot) do
    :ok
  else
    {:error, :item_not_valid_for_slot}
  end
end
defp validate_destination(_item, _to), do: :ok
```

---

### Task 6: Broadcast Visual Updates on Equip

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/move_item_handler.ex`
- Modify: `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex`

**Add to CombatBroadcaster:**
```elixir
@doc """
Broadcast equipment visual change to all nearby players.
"""
@spec broadcast_item_visual_update(non_neg_integer(), non_neg_integer(), [{integer(), integer(), integer(), integer()}], [non_neg_integer()]) :: :ok
def broadcast_item_visual_update(player_guid, zone_id, visuals, recipient_guids) do
  packet = %ServerItemVisualUpdate{
    player_guid: player_guid,
    visuals: visuals
  }

  # Serialize and send to all recipients
  writer = PacketWriter.new()
  {:ok, writer} = ServerItemVisualUpdate.write(packet, writer)
  packet_data = PacketWriter.to_binary(writer)

  send_to_players(recipient_guids, :server_item_visual_update, packet_data)
end
```

---

## Phase 2: Starter Gear

### Task 7: Extract CharacterCreation Item Data

**Files:**
- Create: `apps/bezgelor_data/priv/data/CharacterCreation.json` (extract from game files)
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`

**Data Structure:**
```json
{
  "entries": [
    {
      "id": 1,
      "race": 1,
      "class": 1,
      "faction": 166,
      "item_ids": [12345, 23456, 34567, ...]
    }
  ]
}
```

**Add to Store:**
```elixir
def get_character_creation_items(race, class, faction) do
  # Find matching entry and return item_ids list
end
```

---

### Task 8: Grant Starter Items on Character Create

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex`
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

**Add to CharacterCreateHandler (after character insertion):**
```elixir
# Grant starter gear
starter_items = BezgelorData.Store.get_character_creation_items(race, class, faction)

Enum.each(starter_items, fn item_id ->
  item_info = BezgelorData.Store.get_item(item_id)
  location = if item_info && item_info.is_equippable, do: :equipped, else: :inventory
  Inventory.add_item(character.id, item_id, 1, location)
end)
```

---

### Task 9: Add Item Slot Assignment Logic

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

**When adding equippable items, auto-assign correct slot:**
```elixir
defp find_equip_slot(item_id) do
  item = BezgelorData.Store.get_item(item_id)
  slot_entry = BezgelorData.Store.get_item_slot_entry(item.item_slot_id)

  # Find first available slot from EquippedSlotFlags
  Enum.find(0..15, fn slot ->
    (slot_entry.equipped_slot_flags &&& (1 <<< slot)) != 0
  end)
end
```

---

### Task 10: Verify Starter Gear Appears on Login

**Files:**
- Create: `apps/bezgelor_world/test/integration/starter_gear_test.exs`

**Test that:**
1. New character has items in database
2. ServerPlayerCreate includes inventory items
3. ServerEntityCreate has correct visible_items
4. Gear visuals match equipped item display_ids

---

## Phase 3: Stats Integration

### Task 11: Add Equipment Stats to CharacterStats

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/character_stats.ex`
- Modify: `apps/bezgelor_core/test/character_stats_test.exs`

**Add equipment bonus calculation:**
```elixir
@doc """
Compute combat stats including equipment bonuses.
"""
def compute_combat_stats(character, equipped_items \\ []) do
  base_stats = compute_base_stats(character)
  equipment_bonuses = compute_equipment_bonuses(equipped_items)

  merge_stats(base_stats, equipment_bonuses)
end

defp compute_equipment_bonuses(items) do
  Enum.reduce(items, %{power: 0, tech: 0, armor: 0, ...}, fn item, acc ->
    item_stats = BezgelorData.Store.get_item_stats(item.item_id)
    merge_stats(acc, item_stats)
  end)
end
```

---

### Task 12: Extract Item Stat Data

**Files:**
- Create: `apps/bezgelor_data/priv/data/Item2Stats.json` (from ItemStatEntry)
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`

**Add:**
```elixir
def get_item_stats(item_id) do
  # Return %{power: x, tech: y, armor: z, ...} for item
end
```

---

### Task 13: Wire Equipment Stats into Combat

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`

**When calculating damage, include gear stats:**
```elixir
# Get equipped items for stats
equipped = Inventory.get_items(character_id, :equipped)
stats = CharacterStats.compute_combat_stats(character, equipped)

# Use stats.power, stats.armor, etc. in damage calculation
```

---

## Phase 4: Vendor System

### Task 14: Create EntityVendor Schema and Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/entity_vendor.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/entity_vendor_item.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/vendors.ex`
- Create migration for vendor tables

**Schema:**
```elixir
schema "entity_vendors" do
  field :entity_id, :integer
  field :buy_price_multiplier, :float, default: 1.0
  field :sell_price_multiplier, :float, default: 0.25
end

schema "entity_vendor_items" do
  belongs_to :vendor, EntityVendor
  field :index, :integer
  field :category_index, :integer
  field :item_id, :integer
end
```

---

### Task 15: Create ServerVendorItemsUpdated Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_vendor_items_updated.ex`

**Wire Format:**
```
vendor_guid      : uint32
buy_multiplier   : float32
sell_multiplier  : float32
category_count   : uint8
categories[]     : VendorCategory (localized_name, item_count, items[])
```

---

### Task 16: Create VendorPurchaseHandler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_purchase_handler.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_vendor_purchase.ex`

**Flow:**
1. Parse ClientVendorPurchase (vendor_index, quantity)
2. Look up vendor item from session's selected vendor
3. Calculate cost (item.price * quantity * buy_multiplier)
4. Check player has enough gold
5. Deduct gold, add item to inventory
6. Send ServerItemAdd

---

### Task 17: Create VendorSellHandler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_sell_handler.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_vendor_sell.ex`

**Flow:**
1. Parse ClientVendorSell (item_location, quantity)
2. Get item from player inventory
3. Calculate sell price (item.price * quantity * sell_multiplier)
4. Remove item, add gold
5. Add to buyback list
6. Send ServerItemRemove

---

### Task 18: Create BuybackManager

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/buyback_manager.ex`

**Features:**
- Per-player buyback lists
- Expire after 30 seconds
- Send ServerBuybackItemRemoved on expiry

---

### Task 19: Wire Vendor Interaction

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/npc_handler.ex`

**On interaction event 49 (vendor):**
```elixir
def handle_vendor_open(npc_guid, state) do
  vendor = Vendors.get_vendor_by_entity(npc_guid)
  items = Vendors.get_vendor_items(vendor.id)

  # Store selected vendor in session
  state = put_in(state, [:session_data, :selected_vendor], vendor)

  # Send vendor catalog
  packet = ServerVendorItemsUpdated.new(vendor, items)
  send_packet(packet, state)
end
```

---

## Phase 5: Bank Storage

### Task 20: Create Server0237 (Open Bank UI)

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_open_bank.ex`

**Wire Format:**
```
ui_window_id : uint32  (bank = specific ID from NexusForever)
```

---

### Task 21: Wire Bank Interaction

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/npc_handler.ex`

**On interaction event 66 (personal bank):**
```elixir
def handle_bank_open(state) do
  # Send ServerOpenBank packet
  packet = ServerOpenBank.new()
  send_packet(packet, state)
end
```

---

### Task 22: Extend MoveItemHandler for Bank

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/move_item_handler.ex`

**Support :player_bank location in move validation:**
```elixir
defp validate_destination(_item, %{location: :player_bank}), do: :ok
```

---

## Phase 6: GM Commands

### Task 23: Create /additem Command

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/gm_command_handler.ex`
- Modify command dispatch

**Command format:**
```
/additem <item_id> [quantity]
```

**Implementation:**
```elixir
def handle_additem(item_id, quantity, state) do
  character_id = state.session_data[:character].id

  case Inventory.add_item(character_id, item_id, quantity, :inventory) do
    {:ok, item} ->
      send_item_add(item, state)
      send_chat_message("Added #{quantity}x item #{item_id}", state)

    {:error, :inventory_full} ->
      send_chat_message("Inventory full", state)
  end
end
```

---

### Task 24: Create /equipitem Command

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/gm_command_handler.ex`

**Command format:**
```
/equipitem <item_id>
```

**Implementation:**
```elixir
def handle_equipitem(item_id, state) do
  character_id = state.session_data[:character].id

  # Add directly to equipped location
  case Inventory.add_item(character_id, item_id, 1, :equipped) do
    {:ok, item} ->
      send_item_add(item, state)
      broadcast_visual_update(state)
      send_chat_message("Equipped item #{item_id}", state)

    {:error, reason} ->
      send_chat_message("Failed: #{reason}", state)
  end
end
```

---

## Testing Strategy

### Unit Tests
- Inventory.move_item with various locations
- Inventory.can_equip_in_slot? with item slot flags
- CharacterStats.compute_equipment_bonuses
- All new packet serialization

### Integration Tests
- Character creation grants starter items
- Item equip updates visuals for nearby players
- Vendor buy/sell modifies inventory and gold
- Bank storage persists across sessions

---

## Success Criteria

1. **Gear slots show items** - Equipped items visible in UI
2. **Equip works** - Drag item to slot, see visual change
3. **Stats apply** - Equipped gear affects damage/armor
4. **Starter gear** - New characters have class-appropriate items
5. **Vendors work** - Can buy/sell items from NPCs
6. **Bank works** - Can store items in personal bank
7. **GM commands** - /additem and /equipitem functional

---

## Dependencies

- BezgelorData must have Item2, ItemSlotEntry, CharacterCreation data loaded
- NPC entities must have vendor/bank interaction events wired
- Zone instances must support visual update broadcasting
