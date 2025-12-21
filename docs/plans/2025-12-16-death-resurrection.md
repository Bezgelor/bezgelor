# Death & Resurrection System Implementation Plan

**Created:** 2025-12-16
**Completed:** 2025-12-16
**Phase:** 4 of Combat System Gaps
**Dependencies:** Phase 2 (Aggro Detection), Phase 3 (Combat Movement)
**Status:** ✅ COMPLETE

## Overview

Implement player death handling, respawn mechanics, resurrection spells, and death penalties. When a player's health reaches zero, they enter a death state, can be resurrected by other players, or respawn at their bindpoint with appropriate penalties.

## Architecture

### Modules

| Module | Purpose |
|--------|---------|
| `BezgelorWorld.DeathManager` | GenServer tracking dead players, respawn timers |
| `BezgelorCore.Death` | Pure functions for death penalties, respawn locations |
| `BezgelorWorld.Handler.ResurrectionHandler` | Process resurrection packets |
| `BezgelorProtocol.Packets.World.ServerPlayerDeath` | Death state notification |
| `BezgelorProtocol.Packets.World.ServerResurrect` | Resurrection offer/accept |
| `BezgelorProtocol.Packets.World.ClientResurrect` | Player respawn request |

### Data Sources

- `bindpoints.json` - Respawn locations by zone (already loaded)
- `spells.json` - Resurrection spells with res_percent field
- Character state - Current bindpoint, death count

### Key Packets

| Packet | Direction | Purpose |
|--------|-----------|---------|
| `ServerPlayerDeath` | S→C | Notify player they died |
| `ServerResurrectOffer` | S→C | Show resurrection option (spell or graveyard) |
| `ClientResurrectAccept` | C→S | Player accepts resurrection |
| `ClientResurrectAtBindpoint` | C→S | Player chooses to respawn at bindpoint |
| `ServerResurrect` | S→C | Confirm resurrection, restore health/position |

## Tasks

### Section 1: Death State Management (Tasks 1-4)

#### Task 1: Create Death module with death penalty calculations
**File:** `apps/bezgelor_core/lib/bezgelor_core/death.ex`

```elixir
defmodule BezgelorCore.Death do
  @moduledoc """
  Pure functions for death mechanics.
  """

  @doc """
  Calculate durability loss on death.
  Returns percentage of durability to remove from all equipped items.
  """
  @spec durability_loss(level :: non_neg_integer()) :: float()
  def durability_loss(level) when level < 10, do: 0.0
  def durability_loss(level) when level < 30, do: 5.0
  def durability_loss(level) when level < 50, do: 10.0
  def durability_loss(_level), do: 15.0

  @doc """
  Calculate respawn health percentage.
  Higher level = lower starting health at graveyard respawn.
  """
  @spec respawn_health_percent(level :: non_neg_integer()) :: float()
  def respawn_health_percent(level) when level < 20, do: 50.0
  def respawn_health_percent(level) when level < 40, do: 35.0
  def respawn_health_percent(_level), do: 25.0

  @doc """
  Get nearest bindpoint for zone.
  """
  @spec nearest_bindpoint(zone_id :: non_neg_integer(), position :: {float(), float(), float()}) ::
          {:ok, map()} | :error
end
```

**Test:** `apps/bezgelor_core/test/death_test.exs`
- Test durability loss by level ranges
- Test respawn health percentages
- Test nearest bindpoint lookup

#### Task 2: Create DeathManager GenServer
**File:** `apps/bezgelor_world/lib/bezgelor_world/death_manager.ex`

```elixir
defmodule BezgelorWorld.DeathManager do
  @moduledoc """
  Manages player death state and respawn timers.
  """
  use GenServer

  # State: %{player_guid => %{died_at: timestamp, zone_id: id, position: pos, killer_guid: guid}}

  @doc """
  Mark player as dead.
  """
  @spec player_died(player_guid :: non_neg_integer(), zone_id :: non_neg_integer(),
                    position :: {float(), float(), float()}, killer_guid :: non_neg_integer() | nil) :: :ok

  @doc """
  Offer resurrection to dead player.
  """
  @spec offer_resurrection(player_guid :: non_neg_integer(), caster_guid :: non_neg_integer(),
                           spell_id :: non_neg_integer(), health_percent :: float()) :: :ok | {:error, :not_dead}

  @doc """
  Player accepts resurrection offer.
  """
  @spec accept_resurrection(player_guid :: non_neg_integer()) ::
          {:ok, {position :: tuple(), health_percent :: float()}} | {:error, :no_offer}

  @doc """
  Player respawns at bindpoint.
  """
  @spec respawn_at_bindpoint(player_guid :: non_neg_integer()) ::
          {:ok, {zone_id :: non_neg_integer(), position :: tuple(), health_percent :: float()}} | {:error, :not_dead}

  @doc """
  Check if player is dead.
  """
  @spec is_dead?(player_guid :: non_neg_integer()) :: boolean()
end
```

**Test:** `apps/bezgelor_world/test/death_manager_test.exs`
- Test player_died tracking
- Test resurrection offer/accept flow
- Test respawn at bindpoint

#### Task 3: Wire death detection into combat system
**File:** `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex`

Modify damage handling to detect player death:
```elixir
def handle_player_damage(player_guid, damage, attacker_guid) do
  # Existing damage logic...

  if new_health <= 0 do
    # Player died
    zone_id = get_player_zone(player_guid)
    position = get_player_position(player_guid)

    DeathManager.player_died(player_guid, zone_id, position, attacker_guid)
    broadcast_player_death(player_guid, attacker_guid)
  end
end
```

**Test:** Integration test for damage → death transition

#### Task 4: Create ServerPlayerDeath packet
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_player_death.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPlayerDeath do
  @moduledoc """
  Sent when player dies.
  """

  defstruct [:player_guid, :killer_guid, :death_type]

  # death_type: 0 = combat, 1 = fall, 2 = drown, 3 = environment

  @spec new(player_guid :: non_neg_integer(), killer_guid :: non_neg_integer(),
            death_type :: non_neg_integer()) :: t()

  @behaviour BezgelorProtocol.Writable
end
```

**Test:** Packet write/serialization test

### Section 2: Resurrection Mechanics (Tasks 5-8)

#### Task 5: Create ServerResurrectOffer packet
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_resurrect_offer.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerResurrectOffer do
  @moduledoc """
  Offers resurrection to a dead player.
  """

  defstruct [:caster_guid, :caster_name, :spell_id, :health_percent, :timeout_ms]

  @behaviour BezgelorProtocol.Writable
end
```

**Test:** Packet serialization test

#### Task 6: Create ClientResurrectAccept packet
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_resurrect_accept.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientResurrectAccept do
  @moduledoc """
  Player accepts pending resurrection offer.
  """

  defstruct [:accept]  # true = accept res, false = decline

  @behaviour BezgelorProtocol.Readable
end
```

**Test:** Packet read/deserialization test

#### Task 7: Create ResurrectionHandler
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/resurrection_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.ResurrectionHandler do
  @moduledoc """
  Handles resurrection-related packets.
  """
  @behaviour BezgelorProtocol.Handler

  alias BezgelorWorld.DeathManager
  alias BezgelorProtocol.Packets.World.{ClientResurrectAccept, ServerResurrect}

  @impl true
  def handle(payload, state) do
    # Parse ClientResurrectAccept
    # If accept: call DeathManager.accept_resurrection
    # Send ServerResurrect with new position/health
    # Update player state
  end
end
```

**Test:** Handler test with mock DeathManager

#### Task 8: Wire resurrection spells in SpellHandler
**File:** `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`

Add resurrection spell effect handling:
```elixir
defp apply_spell_effects(caster_guid, target_guid, spell, effects) do
  Enum.reduce(effects, {[], nil}, fn effect, acc ->
    case effect.type do
      :resurrect ->
        handle_resurrect_effect(caster_guid, target_guid, spell, effect)
        acc
      # ... existing cases
    end
  end)
end

defp handle_resurrect_effect(caster_guid, target_guid, spell, effect) do
  health_percent = effect.amount  # e.g., 35.0 for 35% health
  DeathManager.offer_resurrection(target_guid, caster_guid, spell.id, health_percent)
end
```

**Test:** Integration test for resurrection spell casting

### Section 3: Bindpoint Respawn (Tasks 9-12)

#### Task 9: Create ClientResurrectAtBindpoint packet
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_resurrect_at_bindpoint.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientResurrectAtBindpoint do
  @moduledoc """
  Player chooses to respawn at their bindpoint.
  """

  defstruct []  # Empty packet, just the opcode

  @behaviour BezgelorProtocol.Readable
end
```

**Test:** Packet read test

#### Task 10: Implement bindpoint lookup in Death module
**File:** `apps/bezgelor_core/lib/bezgelor_core/death.ex`

```elixir
def nearest_bindpoint(zone_id, {x, y, z}) do
  bindpoints = BezgelorData.Store.get_bindpoints_for_zone(zone_id)

  case bindpoints do
    [] -> :error
    points ->
      nearest = Enum.min_by(points, fn bp ->
        dx = bp.position_x - x
        dy = bp.position_y - y
        dz = bp.position_z - z
        dx * dx + dy * dy + dz * dz
      end)
      {:ok, nearest}
  end
end

def get_character_bindpoint(character_id) do
  # Look up saved bindpoint from character data
  # Fall back to starting zone if none set
end
```

**Test:** Test bindpoint distance calculation and fallback

#### Task 11: Handle bindpoint respawn in ResurrectionHandler
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/resurrection_handler.ex`

Add bindpoint respawn case:
```elixir
def handle(payload, state) do
  case parse_packet(payload) do
    {:resurrect_accept, packet} ->
      handle_accept(packet, state)

    {:resurrect_at_bindpoint, _packet} ->
      handle_bindpoint_respawn(state)
  end
end

defp handle_bindpoint_respawn(state) do
  player_guid = state.session_data[:entity_guid]
  character = state.session_data[:character]

  case DeathManager.respawn_at_bindpoint(player_guid) do
    {:ok, {zone_id, position, health_percent}} ->
      # Apply durability loss
      apply_death_penalty(character)

      # Teleport player to bindpoint
      send_teleport(player_guid, zone_id, position)

      # Restore health
      send_health_update(player_guid, health_percent)

    {:error, :not_dead} ->
      {:ok, state}
  end
end
```

**Test:** Integration test for full respawn flow

#### Task 12: Create ServerResurrect packet
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_resurrect.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerResurrect do
  @moduledoc """
  Confirms resurrection and provides new state.
  """

  defstruct [:resurrect_type, :zone_id, :position_x, :position_y, :position_z, :health_percent]

  # resurrect_type: 0 = spell, 1 = bindpoint, 2 = soulstone

  @behaviour BezgelorProtocol.Writable
end
```

**Test:** Packet serialization test

### Section 4: Death Penalties (Tasks 13-15)

#### Task 13: Implement durability loss on death
**File:** `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

```elixir
def apply_death_durability_loss(character_id) do
  level = get_character_level(character_id)
  loss_percent = BezgelorCore.Death.durability_loss(level)

  if loss_percent > 0 do
    equipped_items = get_equipped_items(character_id)

    Enum.each(equipped_items, fn item ->
      new_durability = max(0, item.durability - (item.max_durability * loss_percent / 100))
      update_item_durability(item.id, new_durability)
    end)
  end

  :ok
end
```

**Test:** Test durability reduction at various levels

#### Task 14: Track death count for resurrection sickness
**File:** `apps/bezgelor_world/lib/bezgelor_world/death_manager.ex`

Add death tracking for potential resurrection sickness:
```elixir
# Add to state: death_counts: %{player_guid => count_in_timeframe}

def get_recent_death_count(player_guid) do
  # Returns number of deaths in last 15 minutes
  # Used for resurrection sickness debuff
end

def apply_resurrection_sickness(player_guid, death_count) do
  # death_count >= 3: apply 25% stat reduction debuff
  # Duration scales with death count
end
```

**Test:** Test death count tracking and decay

#### Task 15: Broadcast player resurrection to zone
**File:** `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex`

```elixir
def broadcast_player_resurrection(player_guid, resurrect_type, position) do
  zone_id = get_player_zone(player_guid)

  # Get nearby players
  nearby = SpatialGrid.entities_in_range(zone_id, position, 100.0)
  player_guids = Enum.filter(nearby, &is_player_guid?/1)

  # Send entity update showing player is alive
  packet = ServerEntityCommand.new(player_guid, :resurrect, position)

  Enum.each(player_guids, fn guid ->
    send_to_player(guid, :server_entity_command, packet)
  end)
end
```

**Test:** Test broadcast to nearby players

### Section 5: Integration (Task 16)

#### Task 16: Full death/resurrection integration test
**File:** `apps/bezgelor_world/test/integration/death_resurrection_test.exs`

```elixir
defmodule BezgelorWorld.Integration.DeathResurrectionTest do
  use ExUnit.Case

  describe "full death flow" do
    test "player dies from combat damage" do
      # Setup player with low health
      # Apply lethal damage
      # Verify DeathManager.is_dead?/1 returns true
      # Verify ServerPlayerDeath packet sent
    end

    test "player accepts resurrection spell" do
      # Kill player
      # Cast resurrection spell on them
      # Verify resurrection offer received
      # Accept resurrection
      # Verify player alive at correct position with correct health
    end

    test "player respawns at bindpoint" do
      # Kill player
      # Request bindpoint respawn
      # Verify teleport to bindpoint
      # Verify durability loss applied
      # Verify reduced health
    end

    test "resurrection sickness after multiple deaths" do
      # Kill player 3+ times in 15 minutes
      # Verify resurrection sickness debuff applied
    end
  end
end
```

## Commit Strategy

Each task = one atomic commit:
- `feat(core): add Death module with penalty calculations`
- `feat(world): add DeathManager GenServer`
- `feat(world): wire death detection into combat system`
- `feat(protocol): add ServerPlayerDeath packet`
- `feat(protocol): add ServerResurrectOffer packet`
- `feat(protocol): add ClientResurrectAccept packet`
- `feat(protocol): add ResurrectionHandler`
- `feat(world): wire resurrection spells in SpellHandler`
- `feat(protocol): add ClientResurrectAtBindpoint packet`
- `feat(core): implement bindpoint lookup`
- `feat(protocol): handle bindpoint respawn`
- `feat(protocol): add ServerResurrect packet`
- `feat(db): implement durability loss on death`
- `feat(world): track death count for resurrection sickness`
- `feat(world): broadcast player resurrection to zone`
- `test(world): add death/resurrection integration tests`

## Success Criteria

1. Players entering death state when health reaches 0
2. Dead players can accept resurrection spells from other players
3. Dead players can respawn at their bindpoint
4. Durability loss applied on bindpoint respawn
5. Resurrection sickness applied after repeated deaths
6. Death/resurrection properly broadcast to nearby players
7. All packets serialize correctly per WildStar protocol
8. Full test coverage for death mechanics
