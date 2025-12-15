# Gear Visuals System

This document describes how character gear is displayed in the character selection screen and how starting gear is assigned to new characters.

## Overview

WildStar characters display equipped gear visuals in the character list. Each piece of equipment has a **display ID** that references a 3D model/texture. The gear visuals system handles:

1. Displaying equipped items on the character selection screen
2. Assigning starting gear to newly created characters
3. Falling back to class-appropriate default visuals when items lack display data

## Architecture

### Data Flow

```
Character Creation                    Character List Display
       │                                      │
       ▼                                      ▼
CharacterCreation.json ──────► Inventory ◄── CharacterListHandler
  (starting item IDs)          (equipped)        │
       │                           │             │
       ▼                           ▼             ▼
Item2Type.json ─────────► slot mapping    get_gear_visuals()
  (type → slot)                                  │
                                                 ▼
                              ┌─────────────────────────────────┐
                              │  Has items with display_id > 0? │
                              └─────────────────────────────────┘
                                    │                │
                                   Yes               No
                                    │                │
                                    ▼                ▼
                              Use inventory    CharacterCreationArmorSet
                              display_ids      (class default visuals)
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| CharacterListHandler | `bezgelor_protocol/handler/character_list_handler.ex` | Builds gear visuals for character list |
| ServerCharacterList | `bezgelor_protocol/packets/world/server_character_list.ex` | Packet containing character data + gear |
| CharacterCreateHandler | `bezgelor_protocol/handler/character_create_handler.ex` | Creates characters with starting gear |
| Store | `bezgelor_data/store.ex` | Item/type lookups and class gear visuals |

### Data Files

| File | Contents |
|------|----------|
| `items.json` | Item definitions with `display_id` and `type_id` |
| `Item2Type.json` | Maps `type_id` to `itemSlotId` (equipment slot) |
| `CharacterCreation.json` | Starting item IDs per race/class/faction |
| `CharacterCreationArmorSet.json` | Default gear display IDs per class |

## Equipment Slots (ItemSlot)

Equipment slots are identified by numeric IDs:

| Slot ID | Name | Description |
|---------|------|-------------|
| 1 | ArmorChest | Chest armor |
| 2 | ArmorLegs | Leg armor |
| 3 | ArmorHead | Helmet/head armor |
| 4 | ArmorShoulder | Shoulder armor |
| 5 | ArmorFeet | Boots/foot armor |
| 6 | ArmorHands | Gloves/hand armor |
| 7 | WeaponTool | Tool weapon slot |
| 20 | WeaponPrimary | Primary weapon |
| 43 | ArmorShields | Shield support system |
| 46 | ArmorGadget | Gadget slot |

## Character Creation Flow

When a character is created:

1. **Template Lookup**: `CharacterCreation.json` is queried by `character_creation_id`
2. **Item Extraction**: Starting items (`itemId0` through `itemId015`) are extracted
3. **Slot Resolution**: For each item, `Store.get_item_slot/1` resolves the slot:
   - Looks up item's `type_id` from `items.json`
   - Looks up `itemSlotId` from `Item2Type.json`
4. **Inventory Population**: Items are added to the `:equipped` container

```elixir
# Example: Starting items for Warrior
itemId0:  81344 → type_id: 16 → slot: 2  (ArmorLegs)
itemId01: 81359 → type_id: 15 → slot: 1  (ArmorChest)
itemId02: 81345 → type_id: 19 → slot: 5  (ArmorFeet)
itemId03: 8534  → type_id: 53 → slot: 43 (ArmorShields)
itemId04: 81346 → type_id: 51 → slot: 20 (WeaponPrimary)
itemId05: 81380 → type_id: 20 → slot: 6  (ArmorHands)
itemId06: 81381 → type_id: 18 → slot: 4  (ArmorShoulder)
```

## Character List Display Flow

When building the character list:

1. **Fetch Characters**: Query all characters for the account/realm
2. **Build Gear Map**: For each character, call `get_gear_visuals(character_id, class_id)`
3. **Inventory Check**: Get equipped items and look up their `display_id`
4. **Fallback Logic**: If no items have `display_id > 0`, use class defaults
5. **Packet Assembly**: Gear visuals are included in `ServerCharacterList`

### Fallback to Class Defaults

Starting items in WildStar have `display_id = 0` (they're placeholder items). The system falls back to `CharacterCreationArmorSet`:

```elixir
# CharacterCreationArmorSet for Warrior (class 1), Arkship gear (set 0)
{
  "classId": 1,
  "creationGearSetEnum": 0,
  "itemDisplayId00": 120,   # WeaponPrimary (slot 20)
  "itemDisplayId01": 4160,  # ArmorChest (slot 1)
  "itemDisplayId02": 4161,  # ArmorLegs (slot 2)
  "itemDisplayId03": 4163,  # ArmorHead (slot 3)
  "itemDisplayId04": 4162,  # ArmorShoulder (slot 4)
  "itemDisplayId05": 4159,  # ArmorFeet (slot 5)
  "itemDisplayId06": 0      # ArmorHands (slot 6) - none
}
```

## ItemVisual Structure

Gear visuals are sent as `ItemVisual` structs:

```elixir
%ItemVisual{
  slot: 1,           # Equipment slot (7 bits)
  display_id: 4160,  # Visual model ID (15 bits)
  colour_set_id: 0,  # Color palette (14 bits)
  dye_data: 0        # Dye channels (32 bits)
}
```

## API Reference

### Store.get_item_slot/1

Gets the equipment slot for an item.

```elixir
@spec get_item_slot(non_neg_integer()) :: non_neg_integer() | nil

# Example
Store.get_item_slot(81344)  # => 2 (ArmorLegs)
```

### Store.get_class_gear_visuals/1

Gets default gear visuals for a character class.

```elixir
@spec get_class_gear_visuals(non_neg_integer()) :: [map()]

# Example
Store.get_class_gear_visuals(1)
# => [
#   %{slot: 20, display_id: 120},
#   %{slot: 1, display_id: 4160},
#   %{slot: 2, display_id: 4161},
#   ...
# ]
```

### CharacterListHandler.get_gear_visuals/2

Gets gear visuals for a character, falling back to class defaults.

```elixir
defp get_gear_visuals(character_id, class_id) :: [ItemVisual.t()]
```

## Implemented Features

### ItemDisplaySource Support

Items with `item_source_id > 0` use level-scaled visuals from the `ItemDisplaySourceEntry` table. The lookup process:

1. Get `item_source_id` from the item
2. Query `ItemDisplaySourceEntry` entries matching that source ID
3. Filter by `Item2TypeId` (equipment type)
4. If multiple matches, find the one where `power_level` falls within `ItemMinLevel`-`ItemMaxLevel` range
5. Return the `ItemDisplayId` from the matching entry

```elixir
# Example: Get display ID for a level-scaled item
display_id = Store.get_item_display_id(item_id, power_level)
```

**Data Requirements**: Extract `ItemDisplaySourceEntry.json` from WildStar client data and place in `apps/bezgelor_data/priv/data/`.

### Gear Mask

The `gear_mask` field on characters controls which gear slots are visible:

- **0xFFFFFFFF** (default): All gear visible
- **0**: Treated as "all visible" for backward compatibility
- Each bit represents a slot; **set bit = visible**, **clear bit = hidden**
- Used by costume system to selectively show/hide gear pieces

Database migration: `20251215052006_add_gear_mask_to_characters.exs`

## Future Improvements

1. **Costume System**: Allow players to override gear appearance with costumes (see GitHub issue)
2. **Dye Support**: Implement `colour_set_id` and `dye_data` for customized gear colors (see GitHub issue)

## Related Files

- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_list_handler.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_list.ex`
- `apps/bezgelor_data/lib/bezgelor_data/store.ex`
- `apps/bezgelor_data/priv/data/items.json`
- `apps/bezgelor_data/priv/data/Item2Type.json`
- `apps/bezgelor_data/priv/data/CharacterCreation.json`
- `apps/bezgelor_data/priv/data/CharacterCreationArmorSet.json`
