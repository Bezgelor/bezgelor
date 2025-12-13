# LLM-Assisted Dungeon Scripting Guide

**Version:** 1.0
**Last Updated:** 2025-12-12

## Overview

This guide documents the process for creating WildStar boss encounter scripts using LLM assistance when original game data is unavailable or incomplete. The Bezgelor project uses an Elixir DSL for defining boss encounters, and this guide provides templates and workflows for generating scripts.

## When to Use LLM Scripting

Use this process when:
- NexusForever doesn't have scripts for the dungeon (most cases)
- Client data extraction yields incomplete ability information
- Community wikis lack detailed mechanical information
- You need to fill in gaps between known abilities

## DSL Quick Reference

### Module Structure

```elixir
defmodule BezgelorWorld.Encounter.Bosses.BossName do
  use BezgelorWorld.Encounter.DSL

  boss "Boss Display Name" do
    boss_id <creature_id>
    health <total_health>
    level <boss_level>
    enrage_timer <ms_until_enrage>
    interrupt_armor <count>

    phase :phase_name, <health_condition> do
      # abilities go here
    end

    on_death do
      loot_table <loot_table_id>
      achievement <achievement_id>
    end
  end
end
```

### Health Conditions

| Condition | Syntax | Description |
|-----------|--------|-------------|
| Above threshold | `health_above: 70` | Active when health > 70% |
| Below threshold | `health_below: 30` | Active when health < 30% |
| Range | `health_between: {30, 70}` | Active when 30% <= health <= 70% |
| Always | `always: true` | Always active (intermission) |

### Ability Definition

```elixir
ability :ability_name, cooldown: <ms>, target: <target_type> do
  # Effects:
  telegraph :shape, radius: <size>, duration: <ms>, color: <color>
  damage <amount>, type: <damage_type>
  debuff :debuff_name, duration: <ms>, stacks: <count>
  movement :knockback, distance: <meters>
  spawn :add, creature_id: <id>, count: <num>
  coordination :stack, min_players: <num>, damage: <shared_damage>
end
```

### Target Types

- `:tank` - Current threat target
- `:healer` - Random healer
- `:random` - Random player
- `:farthest` - Farthest player from boss
- `:nearest` - Nearest player (excluding tank)
- `:highest_threat` - 2nd highest threat
- `:lowest_health` - Lowest health player
- `:all` - All players

### Telegraph Shapes

| Shape | Parameters | Example |
|-------|------------|---------|
| `:circle` | `radius: <m>` | `telegraph :circle, radius: 5, duration: 2000` |
| `:cone` | `angle: <deg>, length: <m>` | `telegraph :cone, angle: 90, length: 15` |
| `:line` | `width: <m>, length: <m>` | `telegraph :line, width: 3, length: 20` |
| `:donut` | `inner_radius: <m>, outer_radius: <m>` | `telegraph :donut, inner_radius: 5, outer_radius: 15` |
| `:room_wide` | none | `telegraph :room_wide, duration: 3000` |
| `:cross` | `width: <m>, length: <m>` | `telegraph :cross, width: 2, length: 20` |

### Telegraph Colors

- `:red` - Unavoidable damage
- `:blue` - Avoidable damage
- `:yellow` - Coordination mechanic
- `:green` - Safe zone
- `:purple` - Debuff application

### Damage Types

- `:physical` - Melee/weapon damage
- `:magic` - Generic magic damage
- `:fire` - Fire element
- `:ice` - Ice element
- `:nature` - Nature/poison
- `:arcane` - Arcane/void

### Movement Effects

```elixir
movement :knockback, distance: 10
movement :knockback, distance: 15, source: :center  # From room center
movement :pull, distance: 20, target: :boss  # Pull to boss
movement :root, duration: 3000
movement :slow, duration: 5000, percent: 50
```

### Spawn Effects

```elixir
spawn :add, creature_id: 2001, count: 2, spread: true, aggro: :healer
spawn :wave, waves: 3, delay: 5000, creature_id: 2002, count_per_wave: 4
```

### Coordination Mechanics

```elixir
coordination :stack, min_players: 3, damage: 30000  # Split damage among stacked players
coordination :spread, required_distance: 8, damage: 6000  # Damage if too close
```

---

## Research Template

Before generating a script, fill out this template:

```json
{
  "dungeon_name": "",
  "boss_name": "",
  "creature_id": 0,
  "level": 0,
  "boss_position_in_dungeon": 0,

  "data_sources": {
    "client_data": false,
    "nexusforever": false,
    "wiki": false,
    "youtube_guides": [],
    "community_posts": []
  },

  "known_abilities": [
    {
      "name": "",
      "description": "",
      "damage_estimate": "",
      "telegraph_shape": "",
      "telegraph_size_estimate": "",
      "cooldown_estimate": "",
      "target_type": "",
      "source": ""
    }
  ],

  "known_phases": [
    {
      "name": "",
      "health_trigger": "",
      "description": "",
      "new_abilities": [],
      "source": ""
    }
  ],

  "special_mechanics": [],

  "add_spawns": [
    {
      "creature_name": "",
      "creature_id": 0,
      "spawn_trigger": "",
      "count": 0,
      "behavior": ""
    }
  ],

  "estimated_health": 0,
  "estimated_enrage_timer": 0,

  "confidence_level": "low|medium|high",
  "notes": ""
}
```

---

## LLM Prompt Template

Use this prompt when asking an LLM to generate a boss script:

```
You are creating a WildStar boss encounter script using Elixir DSL.

## DSL Reference

### Module Structure
```elixir
defmodule BezgelorWorld.Encounter.Bosses.<ModuleName> do
  use BezgelorWorld.Encounter.DSL

  boss "<Display Name>" do
    boss_id <creature_id>
    health <total_health>
    level <level>
    enrage_timer <ms>
    interrupt_armor <count>

    phase :<name>, health_above: <percent> do
      phase_emote "<text>"

      ability :<name>, cooldown: <ms>, target: :<type> do
        telegraph :<shape>, <params>
        damage <amount>, type: :<type>
      end
    end

    on_death do
      loot_table <id>
    end
  end
end
```

### Available Telegraph Shapes
- :circle - radius: <meters>
- :cone - angle: <degrees>, length: <meters>
- :line - width: <meters>, length: <meters>
- :donut - inner_radius: <m>, outer_radius: <m>
- :room_wide - no params
- :cross - width: <m>, length: <m>

### Available Effects
- telegraph - Visual warning area
- damage - Direct damage
- debuff - Apply debuff
- buff - Apply buff (usually to boss)
- movement - Knockback/pull/root
- spawn - Spawn adds
- coordination - Stack/spread mechanics

### Target Types
:tank, :healer, :random, :farthest, :nearest, :highest_threat, :lowest_health, :all

## Example: Stormtalon

```elixir
defmodule BezgelorWorld.Encounter.Bosses.Stormtalon do
  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon" do
    boss_id 17163
    health 500_000
    level 20
    enrage_timer 480_000
    interrupt_armor 2

    phase :one, health_above: 70 do
      phase_emote "Stormtalon screeches and summons lightning!"

      ability :lightning_strike, cooldown: 8000, target: :random do
        telegraph :circle, radius: 5, duration: 2000, color: :red
        damage 5000, type: :magic
      end

      ability :static_charge, cooldown: 15000, target: :tank do
        debuff :static, duration: 10000, stacks: 3
        damage 3000, type: :magic
      end
    end

    phase :two, health_between: {30, 70} do
      inherit_phase :one
      phase_emote "The storm intensifies!"

      ability :eye_of_the_storm, cooldown: 45000 do
        telegraph :donut, inner_radius: 8, outer_radius: 25, duration: 4000
        damage 15000, type: :magic
        spawn :add, creature_id: 2001, count: 2
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      enrage_modifier 1.5

      ability :tempest, cooldown: 15000 do
        telegraph :room_wide, duration: 3000
        movement :knockback, distance: 15, source: :center
      end
    end

    on_death do
      loot_table 17163
    end
  end
end
```

## Boss Information

**Dungeon:** {dungeon_name}
**Boss Name:** {boss_name}
**Creature ID:** {creature_id}
**Level:** {level}

**Known Abilities:**
{ability_list}

**Known Phases:**
{phase_list}

**Special Mechanics:**
{mechanics_list}

## Task

Generate a complete Elixir module for this boss encounter.
- Include all phases with appropriate health triggers
- Create abilities for all known mechanics
- Use appropriate telegraph shapes and sizes
- Set reasonable cooldowns (typically 8-30 seconds)
- Scale damage to boss level (level 20 = 3000-10000 per hit, level 50 = 10000-50000)
- Include phase emotes for transitions

Output ONLY the Elixir code, no explanations.
```

---

## Workflow

### Step 1: Gather Research

1. Check client data extraction for creature ID and any spell references
2. Search community wikis (WildStar Wiki, Fandom)
3. Watch YouTube boss guides (search: "WildStar [Boss Name] guide")
4. Check Reddit/forum posts for mechanic descriptions
5. Fill out the research template

### Step 2: Run LLM Generation

1. Fill in the prompt template with research data
2. Submit to LLM (Claude, GPT-4, etc.)
3. Save the generated Elixir code

### Step 3: Review and Validate

Apply the validation checklist below:

- [ ] Module name matches boss name (PascalCase)
- [ ] boss_id is the correct creature ID from client data
- [ ] health is reasonable for the level (level 20 ≈ 300k-600k, level 50 ≈ 5M-20M)
- [ ] All phases have health conditions
- [ ] Phase conditions don't overlap
- [ ] All abilities have cooldowns
- [ ] Cooldowns are reasonable (5-45 seconds typical)
- [ ] Telegraph sizes are reasonable (3-30 meters typical)
- [ ] Telegraph durations give time to react (1500-4000ms typical)
- [ ] Damage values scale with level
- [ ] No more than 4-6 abilities per phase
- [ ] Coordination mechanics are survivable with proper execution
- [ ] on_death block exists

### Step 4: Test Compilation

```bash
mix compile
```

Fix any compilation errors.

### Step 5: Integration Test

```bash
mix test apps/bezgelor_world/test/encounter/bosses/<boss>_test.exs
```

---

## Validation Checklist Detail

### Timing Guidelines

| Mechanic | Typical Range | Notes |
|----------|---------------|-------|
| Telegraph duration | 1500-4000ms | Longer for harder mechanics |
| Ability cooldown | 5000-45000ms | Main abilities 15-30s |
| Phase transition | 70%, 40%, 20% | Or 70%/30% for 2-phase |
| Enrage timer | 5-10 minutes | 300000-600000ms |
| Add respawn | 30-60 seconds | If recurring |

### Damage Guidelines

| Boss Level | Light Hit | Medium Hit | Heavy Hit | Coordination |
|------------|-----------|------------|-----------|--------------|
| 20 | 2000-4000 | 5000-8000 | 10000-15000 | 20000-30000 |
| 35 | 5000-8000 | 10000-15000 | 20000-30000 | 40000-60000 |
| 50 | 8000-15000 | 20000-35000 | 40000-60000 | 80000-120000 |

### Telegraph Size Guidelines

| Shape | Small | Medium | Large |
|-------|-------|--------|-------|
| Circle | 3-5m | 6-10m | 12-20m |
| Cone | 45°/10m | 90°/15m | 180°/20m |
| Line | 2m/15m | 3m/25m | 5m/40m |
| Donut | 5m/12m | 8m/20m | 10m/30m |

---

## Stormtalon's Lair Reference Data

### Boss Creature IDs

| Boss | Normal ID | Prime ID |
|------|-----------|----------|
| Blade-Wind the Invoker | 17160 | N/A |
| Aethros | 17166 | 32703 |
| Stormtalon | 17163 | 33406 |

### Known Ability Names (from client data)

- Static Wave (Stormtalon)
- Lightning Storm (Stormtalon)
- Manifest Cyclone (Stormtalon)
- Thunder Cross (Blade-Wind)
- Electrostatic Pulse (Blade-Wind)
- Torrent (Aethros)
- Gust of Aethros (Aethros)

### Instance Information

- Instance ID: 12785
- Level Range: 17-20 (Normal), 50 (Prime)
- 5-player dungeon
- 3 bosses

---

## Example: Complete Workflow

### 1. Research for Blade-Wind the Invoker

```json
{
  "dungeon_name": "Stormtalon's Lair",
  "boss_name": "Blade-Wind the Invoker",
  "creature_id": 17160,
  "level": 20,
  "boss_position_in_dungeon": 1,

  "known_abilities": [
    {
      "name": "Thunder Cross",
      "description": "Cross-shaped telegraph attack",
      "telegraph_shape": "cross",
      "telegraph_size_estimate": "20m arms",
      "cooldown_estimate": "20s",
      "source": "wiki + achievement text"
    },
    {
      "name": "Electrostatic Pulse",
      "description": "Pulsing AoE around boss",
      "telegraph_shape": "circle",
      "telegraph_size_estimate": "8m radius",
      "cooldown_estimate": "15s",
      "source": "client text"
    }
  ],

  "known_phases": [
    {
      "name": "Channel Phase",
      "health_trigger": "Periodic invulnerability",
      "description": "Channelers make boss invulnerable, must kill channelers",
      "source": "achievement description"
    }
  ],

  "special_mechanics": [
    "Thundercall Channelers make boss invulnerable",
    "Must kill channelers to damage boss",
    "Lightning Strike can kill channelers (achievement)"
  ],

  "confidence_level": "medium"
}
```

### 2. Generated Script (abbreviated)

```elixir
defmodule BezgelorWorld.Encounter.Bosses.BladeWindTheInvoker do
  use BezgelorWorld.Encounter.DSL

  boss "Blade-Wind the Invoker" do
    boss_id 17160
    health 400_000
    level 20
    enrage_timer 480_000
    interrupt_armor 2

    phase :one, health_above: 75 do
      phase_emote "You dare shed the blood of Stormtalon's disciples?"

      ability :thunder_cross, cooldown: 20000, target: :random do
        telegraph :cross, width: 3, length: 20, duration: 2500, color: :red
        damage 8000, type: :magic
      end

      ability :electrostatic_pulse, cooldown: 15000 do
        telegraph :circle, radius: 8, duration: 2000, color: :blue
        damage 5000, type: :magic
      end
    end

    phase :channel, health_between: {50, 75} do
      phase_emote "Disciples of Stormtalon! Channel the ancient powers!"
      # Boss becomes invulnerable, spawns channelers

      ability :summon_channelers, cooldown: 60000 do
        spawn :add, creature_id: 17161, count: 4, spread: true
        buff :invulnerability, duration: 30000
      end
    end

    # ... more phases

    on_death do
      loot_table 17160
    end
  end
end
```

---

## Troubleshooting

### Common Issues

**Compilation Error: "boss_id is required"**
- Ensure `boss_id` is defined inside the `boss` block

**Compilation Error: "at least one phase is required"**
- Add at least one `phase` block with abilities

**Phase not activating**
- Check health conditions don't overlap
- Verify phase order (highest health first)

**Abilities not firing**
- Check cooldown isn't too long
- Verify phase is active for current health

---

## Contributing

When adding new scripts:

1. Place in `apps/bezgelor_world/lib/bezgelor_world/encounter/bosses/`
2. Follow naming convention: `boss_name.ex` (snake_case)
3. Add test file in `apps/bezgelor_world/test/encounter/bosses/`
4. Update dungeon inventory in the plan document
5. Add research JSON to `apps/bezgelor_data/priv/data/encounters/research/`
