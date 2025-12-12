# Housing System Design

## Summary

Full WildStar-authentic housing system with character-owned sky plots, free-form decor placement, functional FABkits, and four-tier social permissions.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Scope | Full system (Housing + FABkits + Social) |
| Ownership | Character-based (one plot per character) |
| Decor placement | Full free-form (position x/y/z, rotation pitch/yaw/roll, scale) |
| FABkits | All types in schema, Resource/Buffs functional at launch |
| Permissions | Four-tier (Private, Neighbors, Roommates, Public) |
| Instance lifecycle | On-demand with 60-second grace period |
| House types | Two tiers (Cozy, Spacious) |

## Data Model

### Database Tables

**Ownership & Configuration:**
- `housing_plots` - One row per character's plot
- `housing_neighbors` - Join table for neighbor/roommate permissions

**Decor & Placement:**
- `housing_decor` - Each placed decor item with full transform
- `housing_fabkits` - Installed FABkits in the 6 sockets

**Data Files (BezgelorData):**
- `house_types.json` - Cozy/Spacious definitions
- `decor_items.json` - All placeable decor templates
- `fabkit_types.json` - FABkit type definitions

### Schema: housing_plots

```
character_id (FK, unique) - One plot per character
house_type_id (integer) - References house_types.json (1=cozy, 2=spacious)
permission_level (enum) - :private | :neighbors | :roommates | :public
sky_id (integer) - Sky backdrop selection
ground_id (integer) - Ground terrain selection
music_id (integer) - Ambient music selection
rename (string, nullable) - Custom plot name like "Bob's Sanctuary"
created_at, updated_at (timestamps)
```

### Schema: housing_neighbors

```
plot_id (FK) - Which plot this permission is for
character_id (FK) - Who has permission (the neighbor/roommate)
is_roommate (boolean, default false) - Elevated to roommate tier
added_at (timestamp)
unique constraint on (plot_id, character_id)
```

### Schema: housing_decor

```
id (primary key)
plot_id (FK)
decor_id (integer) - Template from decor_items.json
pos_x, pos_y, pos_z (float) - World position
rot_pitch, rot_yaw, rot_roll (float) - Euler angles in degrees
scale (float, default 1.0) - Uniform scale factor
is_exterior (boolean) - Outside vs inside house
placed_at (timestamp)
```

### Schema: housing_fabkits

```
plot_id (FK)
socket_index (integer 0-5) - Which socket (4-5 are large sockets)
fabkit_id (integer) - Template from fabkit_types.json
state (jsonb) - Type-specific state (harvest_available_at, etc.)
installed_at (timestamp)
unique constraint on (plot_id, socket_index)
```

## Context Module: BezgelorDb.Housing

### Plot Lifecycle

- `create_plot(character_id)` - Creates plot with default cozy house
- `get_plot(character_id)` - Returns plot with preloaded decor/fabkits
- `upgrade_house(character_id, house_type_id)` - Validates gold, upgrades to spacious
- `update_plot_theme(character_id, attrs)` - Change sky/ground/music/name
- `set_permission_level(character_id, level)` - Update privacy setting

### Neighbor Management

- `add_neighbor(plot_id, neighbor_character_id)` - Grant visit permission
- `remove_neighbor(plot_id, neighbor_character_id)` - Revoke access
- `promote_to_roommate(plot_id, character_id)` - Upgrade neighbor to roommate
- `demote_from_roommate(plot_id, character_id)` - Downgrade to neighbor
- `list_neighbors(plot_id)` - All neighbors with roommate flag
- `can_visit?(plot_id, visitor_character_id)` - Permission check for entry
- `can_decorate?(plot_id, visitor_character_id)` - Permission check for placement

### Decor Operations

- `place_decor(plot_id, decor_id, placement_attrs)` - Add item, enforces decor limit
- `move_decor(decor_item_id, new_placement_attrs)` - Update position/rotation/scale
- `remove_decor(decor_item_id)` - Delete placed item
- `list_decor(plot_id)` - All placed items for loading instance

### FABkit Operations

- `install_fabkit(plot_id, socket_index, fabkit_id)` - Place FABkit in socket
- `remove_fabkit(plot_id, socket_index)` - Clear socket
- `update_fabkit_state(plot_id, socket_index, state)` - Persist harvest cooldowns, etc.

## Instance Management

### HousingManager GenServer

Singleton that coordinates housing instances across the server.

**State:**
```elixir
%{
  active_instances: %{character_id => instance_pid},
  grace_timers: %{character_id => timer_ref}  # 60-second shutdown delay
}
```

**Operations:**
- `get_or_start_instance(character_id)` - Returns existing or starts new instance
- `enter_housing(visitor_character_id, owner_character_id)` - Permission check + join
- `leave_housing(character_id, owner_character_id)` - Remove from instance, start grace timer if empty

### Instance Startup Flow

1. Load plot from DB via `Housing.get_plot(character_id)`
2. Start `Zone.Instance` with housing zone template
3. Spawn decor entities from `plot.decor` list
4. Spawn FABkit entities from `plot.fabkits` list
5. Register in `active_instances` map

### Instance Shutdown Flow

1. Grace timer fires after 60 seconds empty
2. Persist any dirty FABkit state (harvest cooldowns)
3. Call `Zone.InstanceSupervisor.stop_instance/2`
4. Remove from `active_instances` map

## Protocol Packets

### Plot & Entry

| Packet | Direction | Fields |
|--------|-----------|--------|
| ClientEnterHousing | C→S | owner_character_id |
| ClientLeaveHousing | C→S | (empty) |
| ServerHousingEnter | S→C | plot_data, decor_list, fabkit_list |
| ServerHousingDenied | S→C | reason |

### Decor

| Packet | Direction | Fields |
|--------|-----------|--------|
| ClientPlaceDecor | C→S | decor_id, pos, rot, scale, is_exterior |
| ClientMoveDecor | C→S | decor_item_id, pos, rot, scale |
| ClientRemoveDecor | C→S | decor_item_id |
| ServerDecorPlaced | S→C | decor_item_id, decor_id, pos, rot, scale |
| ServerDecorMoved | S→C | decor_item_id, pos, rot, scale |
| ServerDecorRemoved | S→C | decor_item_id |

### FABkits

| Packet | Direction | Fields |
|--------|-----------|--------|
| ClientInstallFabkit | C→S | socket_index, fabkit_id |
| ClientRemoveFabkit | C→S | socket_index |
| ClientInteractFabkit | C→S | socket_index |
| ServerFabkitInstalled | S→C | socket_index, fabkit_id |
| ServerFabkitRemoved | S→C | socket_index |
| ServerFabkitState | S→C | socket_index, state |

### Social

| Packet | Direction | Fields |
|--------|-----------|--------|
| ClientSetHousingPermission | C→S | level |
| ClientAddNeighbor | C→S | character_name |
| ClientRemoveNeighbor | C→S | character_id |
| ClientPromoteRoommate | C→S | character_id |
| ClientDemoteRoommate | C→S | character_id |
| ServerNeighborList | S→C | neighbors[] |

### Public Listing

| Packet | Direction | Fields |
|--------|-----------|--------|
| ClientRequestPublicPlots | C→S | page, sort_by |
| ServerPublicPlotList | S→C | plots[], total_count, page |

## Handler Flows

### Entry Flow

1. Client sends `ClientEnterHousing{owner_id}`
2. Handler calls `Housing.can_visit?(plot_id, visitor_id)`
3. If denied → `ServerHousingDenied{:not_permitted}`
4. If allowed → `HousingManager.enter_housing(visitor_id, owner_id)`
5. Instance loads, visitor added to player list
6. Handler builds `ServerHousingEnter` with full plot state

### Decor Placement Flow

1. Client sends `ClientPlaceDecor{...}`
2. Handler checks `Housing.can_decorate?(plot_id, character_id)`
3. Handler checks decor limit not exceeded
4. Handler verifies player owns decor_id in inventory
5. `Housing.place_decor(...)` persists to DB
6. Remove item from player inventory
7. Broadcast `ServerDecorPlaced` to all in instance

### FABkit Harvest Flow

1. Client sends `ClientInteractFabkit{socket_index}`
2. Handler loads FABkit state, checks cooldown
3. If on cooldown → send error
4. Grant resources to player inventory
5. Update FABkit state with new cooldown
6. Send `ServerFabkitState` with updated cooldown

## Rested XP & Buff System

### Rested XP Accumulation

Decor items have quality ratings in 5 categories:
- Pride, Ambiance, Aroma, Lighting, Comfort
- Values: 0 (none), 1 (small), 2 (medium), 3 (large)

On logout in housing:
- `Housing.calculate_rested_bonus(plot_id)` finds max rating per category
- Store bonus on character: `rested_xp_rate` (1.0 base + 0.02 per quality point)
- Login-time calculation applies accumulated rested XP

### Buff Board FABkit

Grants 24-hour buffs with player choice:
- 5% PvP XP bonus
- 5% Quest XP bonus
- 10% Dungeon XP bonus

FABkit state stores `buff_granted_at` for 24-hour cooldown.

## Public Listing & Discovery

### Plot Browser

Query public plots with sorting:
- Recently updated
- Most visited
- Random
- Rating (future)

Cache results 30 seconds to reduce DB load.

### Access Methods

- Housing building in capital city
- `/house` command (own plot)
- `/visit CharacterName` command
- Neighbor list "Visit" button

### Visitor Counter

HousingManager tracks current visitors per active instance for real-time display in browser.

## Future Enhancements

### RBAC-Based Permissions

The four-tier system (Private/Neighbors/Roommates/Public) could be replaced with role-based access control for more flexibility:

```elixir
%Role{
  can_visit: boolean,
  can_decorate: boolean,
  can_harvest: boolean,
  can_modify_fabkits: boolean,
  can_manage_permissions: boolean
}
```

This would support:
- Guild housing with officer permissions
- Temporary decorator access for events
- Complex sharing arrangements

### Additional FABkit Types

Once dependent systems exist:
- Crafting stations (requires Tradeskills)
- Expeditions (requires Dungeons)
- Raid portals (requires Raids)
- Challenge courses (requires Challenge system)

### Housing Contests

Community events where players submit plots for judging:
- Screenshot submission
- Community voting
- Themed contests (holidays, etc.)
