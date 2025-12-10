# Phase 7: Mounts, Pets & Storefront Design

## Overview

Two related systems for player collections and monetization:
- **Mounts/Pets**: Collection, summoning, customization, pet auto-combat
- **Storefront**: Premium currency, purchases, gifting, promo codes

## Decisions Made

| Topic | Decision |
|-------|----------|
| Scope | Full WildStar (mounts, hoverboards, pet levels, racing) |
| Pet combat | Auto-combat only (deviation from WildStar - see GitHub issue) |
| Data source | Hybrid: definitions in JSON, storefront/promos in DB |
| Currency | Split: premium account-level, gold character-level |
| Gifting | Friend-only restriction |
| Promo codes | All types: single-use, multi-use, per-account |
| Mount customization | Full: dyes, flair, tricks/trails, upgrades |
| Collections | Hybrid: account-wide for purchases, character for quests |

---

## Data Model

### Mount/Pet Definitions (BezgelorData - static JSON)

```json
// mounts.json
{
  "mounts": [
    {
      "mount_id": 1001,
      "name": "Woolie",
      "type": "ground",
      "base_speed": 1.5,
      "flair_slots": ["head", "saddle", "tail"],
      "unlock_type": "purchasable",
      "customization": {
        "dye_channels": 3,
        "tricks": [],
        "upgrades": ["speed_1", "speed_2"]
      }
    }
  ]
}

// pets.json
{
  "pets": [
    {
      "pet_id": 2001,
      "name": "Rowsdower Pup",
      "category": "critter",
      "base_damage": 10,
      "attack_speed": 2.0,
      "level_curve": [0, 100, 250, 500, 800, 1200]
    }
  ]
}
```

### Player Collections (Database)

```
account_collections:
  - id
  - account_id
  - collectible_type (mount/pet)
  - collectible_id
  - unlock_source (purchase/achievement/promo)
  - unlocked_at

character_collections:
  - id
  - character_id
  - collectible_type
  - collectible_id
  - unlock_source (quest/drop/event)
  - unlocked_at

active_mounts:
  - id
  - character_id
  - mount_id
  - customization (JSON: dyes, flair, upgrades)
  - updated_at

active_pets:
  - id
  - character_id
  - pet_id
  - level
  - xp
  - nickname
  - updated_at
```

### Currency (Database)

```
account_currencies:
  - id
  - account_id
  - premium_currency (NCoin equivalent)
  - bonus_currency (promotional points)
  - updated_at

# Gold remains on Character schema
```

### Storefront Catalog (Database)

```
store_categories:
  - id
  - name
  - sort_order
  - parent_id (nullable, for nesting)

store_items:
  - id
  - category_id
  - name
  - description
  - item_type (mount/pet/costume/bundle/currency_pack)
  - reference_id (mount_id, pet_id, etc.)
  - price_gold
  - price_premium
  - account_wide (boolean)
  - giftable (boolean)
  - available (boolean)
  - featured (boolean)

store_bundles:
  - id
  - bundle_id (FK store_items)
  - included_item_id
  - quantity

store_promotions:
  - id
  - name
  - discount_percent
  - starts_at
  - ends_at
  - applies_to_type (category/item/all)
  - applies_to_id (nullable)

daily_deals:
  - id
  - store_item_id
  - discount_percent
  - deal_date (unique)
```

### Promo Codes (Database)

```
promo_codes:
  - id
  - code (unique string)
  - code_type (single_use/multi_use/per_account)
  - max_uses
  - current_uses
  - rewards (JSON: [{type, id, quantity}])
  - expires_at
  - created_at

promo_redemptions:
  - id
  - code_id
  - account_id
  - redeemed_at
```

### Purchase History (Database)

```
purchase_history:
  - id
  - account_id
  - character_id (nullable)
  - store_item_id
  - currency_type (gold/premium)
  - amount_paid
  - discount_applied
  - is_gift (boolean)
  - gift_recipient_id (nullable)
  - purchased_at
```

---

## Context Layer API

### Collections (`BezgelorDb.Collections`)

```elixir
# Queries
get_account_mounts(account_id) → [mount_ids]
get_character_mounts(char_id) → [mount_ids]
get_all_mounts(account_id, char_id) → merged list
owns_mount?(account_id, char_id, mount_id) → boolean

get_account_pets(account_id) → [pet_ids]
get_character_pets(char_id) → [pet_ids]
get_all_pets(account_id, char_id) → merged list
owns_pet?(account_id, char_id, pet_id) → boolean

# Unlocking
unlock_account_mount(account_id, mount_id, source)
unlock_character_mount(char_id, mount_id, source)
unlock_account_pet(account_id, pet_id, source)
unlock_character_pet(char_id, pet_id, source)
```

### Mounts (`BezgelorDb.Mounts`)

```elixir
get_active_mount(char_id) → {:ok, mount} | nil
set_active_mount(char_id, mount_id) → {:ok, mount} | {:error, reason}
update_customization(char_id, mount_id, changes) → {:ok, mount}
clear_active_mount(char_id) → :ok
```

### Pets (`BezgelorDb.Pets`)

```elixir
get_active_pet(char_id) → {:ok, pet} | nil
set_active_pet(char_id, pet_id) → {:ok, pet} | {:error, reason}
award_pet_xp(char_id, amount) → {:ok, pet, :xp_gained | :level_up}
set_nickname(char_id, nickname) → {:ok, pet}
clear_active_pet(char_id) → :ok
get_pet_level(xp, level_curve) → integer
```

### Storefront (`BezgelorDb.Storefront`)

```elixir
# Catalog
get_categories() → [category]
get_items(category_id, opts) → [item] (with promotions applied)
get_featured_items() → [item]
get_daily_deal() → item | nil
get_item_price(item_id) → {gold, premium, discount}

# Purchasing
purchase_item(account_id, char_id, item_id, currency_type) → {:ok, result} | {:error, reason}
gift_item(from_account, to_char_id, item_id) → {:ok, mail} | {:error, reason}

# Promo codes
redeem_code(account_id, code_string) → {:ok, rewards} | {:error, reason}
validate_code(code_string) → {:ok, code} | {:error, reason}

# Currency
get_premium_balance(account_id) → integer
add_premium_currency(account_id, amount, source) → {:ok, new_balance}
deduct_premium_currency(account_id, amount) → {:ok, new_balance} | {:error, :insufficient}
```

---

## Packets

### Mount Packets

| Packet | Direction | Purpose |
|--------|-----------|---------|
| ServerMountList | S→C | Full collection on login |
| ServerMountUnlocked | S→C | New mount acquired |
| ServerMountSummoned | S→C | Mount spawned (broadcast) |
| ServerMountDismissed | S→C | Mount despawned |
| ServerMountCustomization | S→C | Updated customization |
| ClientSummonMount | C→S | Request to summon |
| ClientDismissMount | C→S | Request to dismiss |
| ClientUpdateMountCustomization | C→S | Change dyes/flair |

### Pet Packets

| Packet | Direction | Purpose |
|--------|-----------|---------|
| ServerPetList | S→C | Full collection on login |
| ServerPetUnlocked | S→C | New pet acquired |
| ServerPetSummoned | S→C | Pet spawned |
| ServerPetDismissed | S→C | Pet despawned |
| ServerPetLevelUp | S→C | Pet gained level |
| ServerPetXpGain | S→C | XP progress |
| ServerPetAttack | S→C | Pet attacked (broadcast) |
| ClientSummonPet | C→S | Request to summon |
| ClientDismissPet | C→S | Request to dismiss |
| ClientSetPetNickname | C→S | Rename pet |

### Storefront Packets

| Packet | Direction | Purpose |
|--------|-----------|---------|
| ServerStoreCategories | S→C | Category tree |
| ServerStoreItems | S→C | Items in category |
| ServerStorePurchaseResult | S→C | Success/failure |
| ServerDailyDeal | S→C | Today's deal |
| ServerPromoCodeResult | S→C | Redemption result |
| ClientRequestStoreItems | C→S | Browse category |
| ClientPurchaseItem | C→S | Buy item |
| ClientGiftItem | C→S | Gift to friend |
| ClientRedeemCode | C→S | Enter promo code |

---

## Pet Auto-Combat Integration

### Combat Flow

```
Player enters combat
    ↓
PetHandler receives {:combat_started, enemy_id}
    ↓
If pet is summoned:
    - Pet targets same enemy as player
    - Pet attacks on interval (attack_speed from def)
    - Damage = base_damage + (level * scaling_factor)
    ↓
On pet attack:
    - CombatHandler.apply_damage(enemy, pet_damage, :pet)
    - Broadcast ServerPetAttack to nearby
    ↓
On enemy death:
    - Pet gets XP share (10% of kill XP)
    - If level up → ServerPetLevelUp
    ↓
Player exits combat → Pet returns to follow mode
```

### Pet State Machine

```
:following ←→ :combat
     ↓
:dismissed
```

### Integration Points

- `CombatHandler` calls `PetHandler.on_combat_start/end`
- `PetHandler` calls `CombatHandler.apply_damage` for attacks
- XP events flow through existing `CombatBroadcaster`

**Note**: Auto-combat is simplified from WildStar's full pet ability system. See [GitHub issue #1](https://github.com/jrimmer/bezgelor/issues/1) for future enhancement.

---

## Purchase Flow

```
ClientPurchaseItem(item_id, currency_type)
    ↓
StorefrontHandler:
    1. Validate item exists and available
    2. Check promotions/daily deal for discounts
    3. Calculate final price
    4. Verify sufficient balance
    ↓
If valid (transaction):
    - Deduct currency
    - Grant item by type:
        mount/pet → Collections.unlock_*
        costume → Inventory.add_item
        currency_pack → add_premium_currency
        bundle → grant each included
    - Record purchase_history
    - ServerStorePurchaseResult(:success)
    ↓
If invalid:
    - ServerStorePurchaseResult(:error, reason)
```

## Gifting Flow

```
ClientGiftItem(item_id, recipient_name)
    ↓
StorefrontHandler:
    1. Resolve recipient → character_id
    2. Verify recipient on sender's friends list
    3. Verify item is giftable
    4. Deduct sender's premium currency
    ↓
If valid:
    - Create gift mail to recipient
    - Record purchase_history (gift: true)
    - ServerStorePurchaseResult(:success)
```

## Promo Code Flow

```
ClientRedeemCode(code_string)
    ↓
StorefrontHandler:
    1. Find code, check not expired
    2. Check code_type rules:
       - single_use: current_uses < 1
       - multi_use: current_uses < max_uses
       - per_account: no prior redemption
    3. Grant rewards
    4. Increment uses, record redemption
    5. ServerPromoCodeResult(:success, rewards)
```

---

## Implementation Order

1. **Schemas & Migrations** - All database tables
2. **Collections Context** - Account/character collection management
3. **Mounts Context + Handler** - Summoning, customization
4. **Pets Context + Handler** - Summoning, XP, auto-combat
5. **Storefront Context** - Catalog, currency
6. **Purchase Handler** - Buy flow, gifting
7. **Promo Codes** - Redemption system
8. **Packets** - All client/server packets
9. **Tests** - Full coverage

---

## Known Deviations from WildStar

| Feature | WildStar | Bezgelor | Reason |
|---------|----------|----------|--------|
| Pet abilities | Player-triggered skills | Auto-combat only | Complexity; tracked in GitHub issue |

---

## Files to Create

| File | Purpose |
|------|---------|
| `bezgelor_db/schema/account_collection.ex` | Account-wide unlocks |
| `bezgelor_db/schema/character_collection.ex` | Character unlocks |
| `bezgelor_db/schema/active_mount.ex` | Active mount + customization |
| `bezgelor_db/schema/active_pet.ex` | Active pet + level/xp |
| `bezgelor_db/schema/account_currency.ex` | Premium currency |
| `bezgelor_db/schema/store_*.ex` | Storefront tables |
| `bezgelor_db/schema/promo_code.ex` | Promo codes |
| `bezgelor_db/collections.ex` | Collections context |
| `bezgelor_db/mounts.ex` | Mounts context |
| `bezgelor_db/pets.ex` | Pets context |
| `bezgelor_db/storefront.ex` | Storefront context |
| `bezgelor_world/handler/mount_handler.ex` | Mount handler |
| `bezgelor_world/handler/pet_handler.ex` | Pet handler |
| `bezgelor_world/handler/storefront_handler.ex` | Store handler |
| `bezgelor_protocol/packets/world/server_mount_*.ex` | Mount packets |
| `bezgelor_protocol/packets/world/server_pet_*.ex` | Pet packets |
| `bezgelor_protocol/packets/world/server_store_*.ex` | Store packets |
