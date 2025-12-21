# BezgelorCore

Shared types and game logic used across all Bezgelor applications.

## Features

- Common types: Vector3, Entity, Position
- Game mechanics: Spell calculations, Combat, AI
- Experience and leveling calculations
- Damage/healing formulas
- Faction and reputation logic

## Key Modules

- `BezgelorCore.Vector3` - 3D coordinate type
- `BezgelorCore.Spell` - Spell effect calculations
- `BezgelorCore.Combat` - Combat resolution logic
- `BezgelorCore.XP` - Experience and leveling

## Usage

```elixir
# Vector math
pos = BezgelorCore.Vector3.new(100.0, 50.0, 200.0)
distance = BezgelorCore.Vector3.distance(pos, target_pos)

# Damage calculation
damage = BezgelorCore.Combat.calculate_damage(spell, caster_stats, target_stats)
```
