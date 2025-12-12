# Phase 8: Spell System

## Overview

Implement the foundation for spell casting, effects, and cooldowns. This phase focuses on the core spell mechanics that enable combat.

## Goals

1. Define spell data structures and static data loading
2. Implement spell casting packets and validation
3. Create cooldown tracking system
4. Implement basic spell effects (damage, healing)
5. Add spell handler to process cast requests

## Architecture

### Modules

```
bezgelor_core/
├── spell.ex           # Spell struct and definitions
├── spell_effect.ex    # Effect types and calculations
└── cooldown.ex        # Cooldown tracking logic

bezgelor_world/
├── spell_manager.ex   # GenServer for spell state
└── handler/
    └── spell_handler.ex  # Handles spell casting packets
```

### Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0400 | ClientCastSpell | C→S | Player initiates spell cast |
| 0x0401 | ServerSpellStart | S→C | Cast started (shows cast bar) |
| 0x0402 | ServerSpellFinish | S→C | Cast completed |
| 0x0403 | ServerSpellEffect | S→C | Spell effect applied |
| 0x0404 | ServerCastResult | S→C | Cast success/failure |
| 0x0405 | ClientCancelCast | C→S | Player cancels cast |
| 0x0406 | ServerCooldown | S→C | Cooldown update |

## Data Structures

### Spell Definition

```elixir
defmodule BezgelorCore.Spell do
  defstruct [
    :id,                    # Unique spell identifier
    :name,                  # Display name
    :description,           # Tooltip text
    :cast_time,             # Milliseconds (0 = instant)
    :cooldown,              # Milliseconds
    :gcd,                   # Global cooldown (true/false)
    :range,                 # Max range in units (0 = self)
    :resource_cost,         # Mana/energy cost
    :resource_type,         # :mana | :energy | :focus | :none
    :target_type,           # :self | :enemy | :ally | :ground | :aoe
    :aoe_radius,            # For AoE spells
    :effects,               # List of effect definitions
    :interrupt_flags,       # What can interrupt this cast
    :spell_school           # :physical | :magic | :tech
  ]
end
```

### Spell Effect

```elixir
defmodule BezgelorCore.SpellEffect do
  defstruct [
    :type,           # :damage | :heal | :buff | :debuff | :dot | :hot
    :amount,         # Base amount
    :scaling,        # Stat scaling coefficient
    :scaling_stat,   # :power | :tech | :support
    :duration,       # For over-time effects (ms)
    :tick_interval,  # For DoT/HoT (ms)
    :school          # Damage school for resistances
  ]
end
```

### Cast State

```elixir
# Tracked per player during active cast
%{
  spell_id: integer(),
  target_guid: integer() | nil,
  target_position: {float, float, float} | nil,
  start_time: integer(),  # monotonic time
  duration: integer(),    # ms
  interrupted: boolean()
}
```

### Cooldown State

```elixir
# Tracked per spell per player
%{
  spell_id => expires_at  # monotonic time when cooldown ends
}
```

## Spell Casting Flow

```
1. CLIENT: Sends ClientCastSpell {spell_id, target_guid, target_pos}

2. SERVER VALIDATION:
   ├─ Player knows spell?
   ├─ Cooldown expired?
   ├─ Resources available?
   ├─ Target valid (if required)?
   ├─ Range check?
   └─ Not already casting?

3. If validation fails:
   └─ Send ServerCastResult {result: :failed, reason: atom()}

4. If instant cast (cast_time == 0):
   ├─ Apply effects immediately
   ├─ Deduct resources
   ├─ Apply cooldown
   ├─ Send ServerSpellFinish
   └─ Send ServerSpellEffect to affected targets

5. If cast time > 0:
   ├─ Start cast state
   ├─ Send ServerSpellStart (cast bar)
   ├─ Schedule completion timer
   └─ Monitor for interrupts

6. On cast completion:
   ├─ Validate target still valid
   ├─ Deduct resources
   ├─ Apply cooldown
   ├─ Calculate effects
   ├─ Apply to target(s)
   ├─ Send ServerSpellFinish
   └─ Broadcast ServerSpellEffect

7. On interrupt/cancel:
   ├─ Clear cast state
   ├─ Partial resource refund (optional)
   └─ Send ServerCastResult {result: :interrupted}
```

## Effect Calculations

### Damage Formula

```elixir
def calculate_damage(spell_effect, caster, target) do
  base = spell_effect.amount

  # Stat scaling
  stat_bonus = get_stat(caster, spell_effect.scaling_stat) * spell_effect.scaling
  scaled = base + stat_bonus

  # Critical hit (simplified)
  crit_chance = get_crit_chance(caster)
  {damage, is_crit} =
    if :rand.uniform(100) <= crit_chance do
      {scaled * 1.5, true}
    else
      {scaled, false}
    end

  # Target armor/resistance (simplified)
  mitigation = get_mitigation(target, spell_effect.school)
  final = damage * (1 - mitigation)

  {trunc(final), is_crit}
end
```

### Healing Formula

```elixir
def calculate_healing(spell_effect, caster, _target) do
  base = spell_effect.amount
  stat_bonus = get_stat(caster, spell_effect.scaling_stat) * spell_effect.scaling
  scaled = base + stat_bonus

  crit_chance = get_crit_chance(caster)
  {healing, is_crit} =
    if :rand.uniform(100) <= crit_chance do
      {scaled * 1.5, true}
    else
      {scaled, false}
    end

  {trunc(healing), is_crit}
end
```

## Static Spell Data

For Phase 8, we'll define a small set of test spells:

| ID | Name | Cast | CD | Range | Type | Effect |
|----|------|------|-----|-------|------|--------|
| 1 | Fireball | 2000 | 5000 | 30 | enemy | 100 damage |
| 2 | Heal | 1500 | 0 | 30 | ally | 150 heal |
| 3 | Quick Strike | 0 | 3000 | 5 | enemy | 50 damage |
| 4 | Shield | 0 | 30000 | 0 | self | +100 absorb |
| 5 | Regen | 2000 | 10000 | 0 | self | 25 heal/sec for 10s |

## Packet Formats

### ClientCastSpell (0x0400)

```
spell_id      : uint32  - Spell to cast
target_guid   : uint64  - Target entity (0 for ground/self)
target_x      : float32 - Ground target X (for AoE)
target_y      : float32 - Ground target Y
target_z      : float32 - Ground target Z
```

### ServerSpellStart (0x0401)

```
caster_guid   : uint64  - Who is casting
spell_id      : uint32  - Spell being cast
cast_time     : uint32  - Duration in ms
target_guid   : uint64  - Target (if any)
```

### ServerSpellFinish (0x0402)

```
caster_guid   : uint64  - Who cast
spell_id      : uint32  - Spell that finished
```

### ServerSpellEffect (0x0403)

```
caster_guid   : uint64  - Caster
target_guid   : uint64  - Target affected
spell_id      : uint32  - Spell
effect_type   : uint8   - 0=damage, 1=heal, 2=buff, 3=debuff
amount        : int32   - Damage/healing amount
flags         : uint8   - 0x01=crit, 0x02=absorb, 0x04=miss
```

### ServerCastResult (0x0404)

```
result        : uint8   - 0=ok, 1=failed, 2=interrupted
reason        : uint8   - Failure reason code
spell_id      : uint32  - Spell attempted
```

### ClientCancelCast (0x0405)

```
(empty payload - cancel current cast)
```

### ServerCooldown (0x0406)

```
spell_id      : uint32  - Spell with cooldown
remaining     : uint32  - Milliseconds remaining
```

## Cast Result Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | ok | Cast succeeded |
| 1 | failed | Generic failure |
| 2 | interrupted | Cast was interrupted |
| 3 | not_known | Spell not learned |
| 4 | cooldown | Spell on cooldown |
| 5 | no_target | Target required |
| 6 | invalid_target | Wrong target type |
| 7 | out_of_range | Target too far |
| 8 | no_resources | Not enough mana/energy |
| 9 | silenced | Cannot cast spells |
| 10 | moving | Cannot cast while moving |

## Implementation Tasks

### Task 1: Add Spell Opcodes

Add to `bezgelor_protocol/opcode.ex`:
- 0x0400-0x0406 for spell packets

### Task 2: Create Spell Module

Create `bezgelor_core/spell.ex`:
- Spell struct definition
- Test spell definitions (hardcoded for Phase 8)
- Spell lookup by ID

### Task 3: Create SpellEffect Module

Create `bezgelor_core/spell_effect.ex`:
- Effect type definitions
- Damage/healing calculation functions
- Pure functions, no state

### Task 4: Create Cooldown Module

Create `bezgelor_core/cooldown.ex`:
- Cooldown state struct
- Check/set/clear cooldown functions
- GCD handling

### Task 5: Define Spell Packets

Create in `bezgelor_protocol/packets/world/`:
- `client_cast_spell.ex` (Readable)
- `server_spell_start.ex` (Writable)
- `server_spell_finish.ex` (Writable)
- `server_spell_effect.ex` (Writable)
- `server_cast_result.ex` (Writable)
- `client_cancel_cast.ex` (Readable)
- `server_cooldown.ex` (Writable)

### Task 6: Create SpellManager

Create `bezgelor_world/spell_manager.ex`:
- GenServer for spell casting state
- Manages active casts per player
- Handles cast completion timers
- Tracks cooldowns

### Task 7: Create SpellHandler

Create `bezgelor_world/handler/spell_handler.ex`:
- Handles ClientCastSpell
- Handles ClientCancelCast
- Validates and initiates casts
- Coordinates with SpellManager

### Task 8: Entity Health Updates

Extend Entity module to:
- Track health/max_health
- Apply damage/healing
- Handle death state

### Task 9: Integration Tests

- Test spell casting flow
- Test cooldown tracking
- Test instant vs cast-time spells
- Test interrupt/cancel
- Test damage/healing calculations

## Future Phases

Phase 8 implements the foundation. Future phases will add:

- **Phase 9+**: Buffs/debuffs with duration
- **Phase 9+**: DoT/HoT effects
- **Phase 9+**: AoE targeting and multi-target effects
- **Phase 9+**: Creature AI spell casting
- **Phase 9+**: Combat log and damage meters
- **Phase 9+**: Talent system modifying spells

## Success Criteria

- Player can cast instant spells
- Player can cast spells with cast time
- Cast bar shows during cast-time spells
- Cooldowns prevent immediate recast
- Damage reduces target health
- Healing restores target health
- Cast can be interrupted/cancelled
- All spell tests pass
