# Phase 8: Tradeskills System Design

**Created:** 2025-12-11
**Status:** Approved
**Goal:** Full fidelity WildStar tradeskill implementation with server-configurable behaviors

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Fidelity level | Full WildStar replication | Coordinate-based crafting, discovery, overcharge, tech trees |
| Profession limits | Configurable | Server admin sets max crafting/gathering, swap behavior |
| Discovery scope | Configurable | Character-based or account-based per server config |
| Coordinate hit detection | Rectangle-based | Full coordinates in static data, simplified runtime logic |
| Node competition | Configurable | First-tap, shared, or instanced per server config |
| Work orders | Hybrid generation | Static pool, random daily selection by profession tier |
| Tech tree respec | Configurable | Free, gold cost, item required, or disabled |
| Crafting stations | Configurable | Strict, universal, or housing-bypass mode |
| Achievements | Integrated | Uses existing achievement system with new criteria types |

**Design Note:** Coordinate hit detection uses rectangle-based checks rather than complex polygon math. This may differ from the original WildStar implementation but provides equivalent gameplay with simpler logic.

---

## Configuration

All major tradeskill behaviors are server-configurable via `config/runtime.exs`:

```elixir
config :bezgelor_world, :tradeskills,
  # Profession limits
  max_crafting_professions: 2,        # 0 = unlimited
  max_gathering_professions: 3,       # 0 = unlimited
  preserve_progress_on_swap: false,   # true = keep XP when switching

  # Discovery scope
  discovery_scope: :character,        # :character | :account

  # Node competition
  node_competition: :first_tap,       # :first_tap | :shared | :instanced
  shared_tap_window_seconds: 5,       # for :shared mode

  # Tech tree respec
  respec_policy: :gold_cost,          # :free | :gold_cost | :item_required | :disabled
  respec_gold_cost: 10_00,            # in copper (10 gold)
  respec_item_id: nil,                # item ID if :item_required

  # Crafting stations
  station_mode: :strict               # :strict | :universal | :housing_bypass
```

---

## Database Schemas

### character_tradeskill

Tracks profession progress per character.

```elixir
schema "character_tradeskills" do
  belongs_to :character, Character
  field :profession_id, :integer        # from static data
  field :profession_type, Ecto.Enum, values: [:crafting, :gathering]
  field :skill_level, :integer, default: 0
  field :skill_xp, :integer, default: 0
  field :is_active, :boolean, default: true  # false if swapped away
  timestamps()
end
```

### schematic_discovery

Tracks discovered recipes and variants.

```elixir
schema "schematic_discoveries" do
  belongs_to :character, Character       # or account_id based on config
  field :account_id, :integer            # populated if discovery_scope: :account
  field :schematic_id, :integer          # base schematic from static data
  field :variant_id, :integer, default: 0  # 0 = base, >0 = discovered variant
  field :discovered_at, :utc_datetime
  timestamps()
end
```

### tradeskill_talent

Spent tech tree points.

```elixir
schema "tradeskill_talents" do
  belongs_to :character, Character
  field :profession_id, :integer
  field :talent_id, :integer             # from static data
  field :points_spent, :integer, default: 1
  timestamps()
end
```

### work_order

Active and completed work orders.

```elixir
schema "work_orders" do
  belongs_to :character, Character
  field :work_order_id, :integer         # from static data
  field :profession_id, :integer
  field :quantity_required, :integer
  field :quantity_completed, :integer, default: 0
  field :status, Ecto.Enum, values: [:active, :completed, :expired]
  field :expires_at, :utc_datetime
  field :accepted_at, :utc_datetime
  timestamps()
end
```

### Crafting Session (In-Memory)

Crafting sessions are transient, stored in the player's GenServer state. If a player disconnects mid-craft, the session is lost (matching original behavior).

```elixir
%CraftingSession{
  schematic_id: integer,
  cursor_x: float,          # current position, starts at 0,0
  cursor_y: float,
  additives_used: [%{item_id, quantity, vector_x, vector_y}],
  overcharge_level: integer,  # 0 = none, higher = more risk/reward
  started_at: DateTime
}
```

---

## Static Data (from .tbl extraction)

Load into ETS via `bezgelor_data`:

| Table | Source .tbl | Purpose |
|-------|-------------|---------|
| `tradeskill_profession` | TradeskillTier.tbl | Profession definitions, level caps |
| `tradeskill_schematic` | TradeskillSchematic2.tbl | Recipe definitions, coordinate grids |
| `tradeskill_material` | TradeskillMaterial.tbl | Additive effects (X/Y vectors) |
| `tradeskill_tier` | TradeskillTier.tbl | Skill thresholds, unlocks |
| `tradeskill_talent` | TradeskillTalent.tbl | Tech tree nodes and bonuses |
| `tradeskill_bonus` | TradeskillBonus.tbl | Stat bonuses for coordinate zones |
| `gathering_node` | HarvestingNode.tbl | Node types, loot tables, skill requirements |
| `work_order_pool` | TradeskillWorkOrder.tbl | Work order templates by tier |

### Schematic Structure

```elixir
%{
  schematic_id: 1234,
  profession_id: 1,
  tier: 3,
  base_item_id: 5678,
  grid_width: 100,
  grid_height: 100,
  target_zones: [
    %{id: 1, x_min: 40, x_max: 60, y_min: 40, y_max: 60,
      variant_id: 0, quality: :standard},
    %{id: 2, x_min: 70, x_max: 85, y_min: 70, y_max: 85,
      variant_id: 101, quality: :exceptional},
  ],
  required_materials: [%{item_id: 100, quantity: 2}],
  optional_additive_slots: 4
}
```

---

## Crafting Coordinate System

### Crafting Flow

1. Player initiates craft at station → validate profession, skill level, materials
2. Base materials consumed immediately
3. Player adds additives (optional) → each shifts cursor by its X/Y vector
4. Player can "overcharge" to amplify vectors (increases failure chance)
5. Player finalizes → hit detection determines outcome zone
6. Zone determines: output item variant, quality tier, bonus stats
7. If zone is undiscovered variant → permanently unlock it
8. Grant tradeskill XP (modified by tech tree bonuses)
9. Check achievement criteria (items crafted, variants discovered)

### Hit Detection (Rectangle-Based)

```elixir
def find_target_zone(cursor_x, cursor_y, zones) do
  Enum.find(zones, fn zone ->
    cursor_x >= zone.x_min and cursor_x <= zone.x_max and
    cursor_y >= zone.y_min and cursor_y <= zone.y_max
  end)
end
```

If no zone matched, craft fails (materials lost). Overcharge increases vectors but adds failure chance roll before hit detection.

---

## Gathering System

### Node State (per ZoneInstance)

```elixir
%GatheringNode{
  node_id: integer,           # unique instance ID
  node_type_id: integer,      # from static data
  position: Vector3,
  respawn_at: DateTime | nil, # nil = available
  tapped_by: character_id | nil,
  tap_expires_at: DateTime | nil
}
```

### Gathering Flow

1. Player interacts with node → validate skill level requirement
2. Based on `node_competition` config:
   - `:first_tap` → claim exclusively, others blocked
   - `:shared` → start tap window, multiple players can harvest
   - `:instanced` → each player has separate node state
3. Gathering cast time (interruptible)
4. On success: generate loot from node's loot table, grant gathering XP
5. Node enters respawn timer (or removed if instanced)
6. Check achievement criteria

Loot generation uses existing loot system from Phase 6 with gathering-specific loot tables.

---

## Tech Trees

### Structure

Each profession has a tech tree with nodes connected in a graph. Nodes have:
- Prerequisites (other nodes that must be unlocked first)
- Point cost (usually 1)
- Bonus type and value

### Bonus Types

| Bonus Type | Effect |
|------------|--------|
| `material_reduction` | % chance to not consume an additive |
| `xp_bonus` | % increased tradeskill XP |
| `success_chance` | % reduced failure chance on overcharge |
| `quality_bonus` | % chance to upgrade output quality tier |
| `discovery_chance` | % bonus to variant discovery (if near zone edge) |
| `gathering_speed` | % reduced gather cast time |
| `gathering_yield` | % chance for bonus materials |

### Point Allocation

```elixir
def allocate_talent(character, profession_id, talent_id) do
  with :ok <- validate_profession_active(character, profession_id),
       :ok <- validate_available_points(character, profession_id),
       :ok <- validate_prerequisites(character, profession_id, talent_id),
       :ok <- validate_not_already_maxed(character, talent_id) do
    Tradeskills.add_talent_point(character.id, profession_id, talent_id)
  end
end
```

Respec (based on config) clears all talents for the profession and refunds points.

---

## Work Orders

### Daily Generation

A scheduled job runs at server reset time (configurable, default midnight UTC):

1. For each character with active crafting professions
2. Determine their tier in each profession
3. Select 3 random work orders from that tier's pool
4. Create work_order records with 24-hour expiry

### Work Order Structure (Static Data)

```elixir
%{
  work_order_id: 501,
  profession_id: 1,
  tier: 3,
  schematic_id: 1234,        # what to craft
  quantity: 5,
  xp_reward: 500,
  gold_reward: 50_00,
  item_rewards: [%{item_id: 999, quantity: 1}]
}
```

### Completion Flow

When a player crafts an item, check if it matches any active work order schematic. If so, increment `quantity_completed`. When complete, grant rewards and mark status.

---

## Achievement Integration

### New Criteria Types

```elixir
:craft_item           # Craft any item (count)
:craft_profession     # Craft items in specific profession (count)
:craft_schematic      # Craft specific schematic (count)
:discover_variant     # Discover any variant (count)
:profession_level     # Reach level X in any profession
:profession_max       # Max out a profession
:complete_work_order  # Complete work orders (count)
:gather_node          # Gather from nodes (count)
:gather_type          # Gather specific material type (count)
```

### Integration Points

- After successful craft → check `:craft_*` criteria
- After variant discovery → check `:discover_variant`
- After skill level up → check `:profession_level`, `:profession_max`
- After work order complete → check `:complete_work_order`
- After gathering → check `:gather_*`

Uses existing `BezgelorWorld.AchievementManager.check_criteria/3` pattern.

---

## Packets

### Client → Server

| Packet | Purpose |
|--------|---------|
| `ClientTradeskillLearn` | Learn a new profession |
| `ClientTradeskillSwap` | Switch active profession |
| `ClientCraftStart` | Begin crafting a schematic |
| `ClientCraftAddAdditive` | Add additive to current session |
| `ClientCraftOvercharge` | Increase overcharge level |
| `ClientCraftFinalize` | Complete the craft |
| `ClientCraftCancel` | Abandon crafting session |
| `ClientGatherStart` | Begin gathering from node |
| `ClientGatherCancel` | Cancel gathering |
| `ClientTalentAllocate` | Spend tech tree point |
| `ClientTalentRespec` | Reset tech tree |
| `ClientWorkOrderAccept` | Accept a work order |
| `ClientWorkOrderAbandon` | Abandon work order |

### Server → Client

| Packet | Purpose |
|--------|---------|
| `ServerTradeskillUpdate` | Profession list, levels, XP |
| `ServerSchematicList` | Known schematics for profession |
| `ServerCraftSession` | Current crafting state (cursor, additives) |
| `ServerCraftResult` | Craft outcome (success/fail, item, discoveries) |
| `ServerGatherResult` | Gathering loot |
| `ServerTalentUpdate` | Tech tree state |
| `ServerWorkOrderList` | Available/active work orders |
| `ServerWorkOrderUpdate` | Progress update |
| `ServerNodeSpawn` | Gathering node appeared |
| `ServerNodeDespawn` | Node harvested/despawned |

---

## Module Structure

```
apps/bezgelor_db/lib/bezgelor_db/
├── schema/
│   ├── character_tradeskill.ex
│   ├── schematic_discovery.ex
│   ├── tradeskill_talent.ex
│   └── work_order.ex
├── tradeskills.ex              # Context module (public API)

apps/bezgelor_data/lib/bezgelor_data/
├── tradeskill_data.ex          # ETS loading for tradeskill static data

apps/bezgelor_world/lib/bezgelor_world/
├── crafting/
│   ├── crafting_session.ex     # Session struct and logic
│   ├── coordinate_system.ex    # Hit detection, vector math
│   └── overcharge.ex           # Overcharge risk calculation
├── gathering/
│   ├── gathering_node.ex       # Node struct
│   └── node_manager.ex         # Per-zone node spawning/respawn
├── tradeskill_manager.ex       # Profession management
├── tech_tree_manager.ex        # Talent allocation
├── work_order_manager.ex       # Daily generation, completion
├── handler/
│   ├── tradeskill_handler.ex   # Packet handlers
│   ├── crafting_handler.ex
│   └── gathering_handler.ex

apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/
├── client_tradeskill_*.ex      # Client packets
├── server_tradeskill_*.ex      # Server packets
├── client_craft_*.ex
├── server_craft_*.ex
├── client_gather_*.ex
└── server_gather_*.ex
```

---

## Data Extraction Tasks

Extract from archive before implementation:

1. `TradeskillTier.tbl` → profession definitions, tier thresholds
2. `TradeskillSchematic2.tbl` → schematics with coordinate grids
3. `TradeskillMaterial.tbl` → additive X/Y vectors
4. `TradeskillTalent.tbl` → tech tree structure
5. `TradeskillBonus.tbl` → zone bonus definitions
6. `TradeskillWorkOrder.tbl` → work order templates (if exists)
7. `HarvestingNode.tbl` → gathering node definitions

Extend `tbl_extractor.py` if any of these have unique structures.

---

## Implementation Order

1. **Data extraction** - Extract .tbl files, create JSON, verify structure
2. **Static data loading** - Add to bezgelor_data ETS store
3. **Database schemas** - Create schemas and migration
4. **Tradeskills context** - CRUD operations in bezgelor_db
5. **Gathering system** - Node spawning, collection, respawn (simpler, good foundation)
6. **Crafting core** - Session management, coordinate system, hit detection
7. **Tech trees** - Talent allocation, bonus application
8. **Work orders** - Generation, tracking, completion
9. **Packets** - All client/server packet definitions
10. **Handlers** - Wire up packet handlers
11. **Achievement integration** - Add criteria types, hook into existing system
12. **Testing** - Unit tests for coordinate math, integration tests for full flows
