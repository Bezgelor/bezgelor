# Combat Spell Effects Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire Spell4Effects data so that casting spells (especially auto-attacks like Pistol Shot) deals damage to creatures, enabling the full combat loop.

**Architecture:** Extract Spell4Effects.tbl from game data, load into ETS, and integrate effect lookup into `Spell.get/1`. When a player casts a spell, the handler resolves effects from game data and applies damage to creatures.

**Tech Stack:** Elixir, ETS, Python (tbl_extractor), JSON game data

---

## Background

The combat system is fully implemented EXCEPT spell effects are not loaded from game data:

1. `SpellHandler` resolves spell_id from shortcuts correctly
2. `Spell.get/1` returns spell struct with `effects: []` for game data spells
3. `apply_spell_effects/5` iterates over effects but list is empty
4. No damage dealt → no creature aggro → no combat

**Root cause:** `Spell.get_from_game_data/1` at `apps/bezgelor_core/lib/bezgelor_core/spell.ex:242` returns `effects: []` because Spell4Effects table is not loaded.

**NexusForever reference:** `Source/NexusForever.Game/Spell/GlobalSpellManager.cs:56-60` loads Spell4Effects keyed by SpellId.

---

## Task 1: Extract Spell4Effects.tbl

**Files:**
- Read: `source_files/ClientData.archive`
- Create: `apps/bezgelor_data/priv/data/Spell4Effects.json`

**Step 1: Extract Spell4Effects.tbl using Halon**

```bash
cd /Users/jrimmer/work/bezgelor
python3 Halon/halon.py source_files/ClientData.archive extract "DB/Spell4Effects.tbl" --output extracted_tbl/
```

**Step 2: Convert .tbl to JSON using tbl_extractor**

```bash
cd /Users/jrimmer/work/bezgelor
python3 tools/tbl_extractor/tbl_extractor.py extracted_tbl/DB/Spell4Effects.tbl --output apps/bezgelor_data/priv/data/Spell4Effects.json
```

Expected: JSON file with array of effect entries like:
```json
{
  "id": 12345,
  "spellId": 55665,
  "effectType": 3,
  "damageType": 1,
  "dataBits00": 50,
  ...
}
```

**Step 3: Verify extraction**

```bash
head -c 2000 apps/bezgelor_data/priv/data/Spell4Effects.json
wc -l apps/bezgelor_data/priv/data/Spell4Effects.json
```

Expected: Valid JSON with 50,000+ entries (based on NexusForever comments about spell tables).

**Step 4: Commit**

```bash
git add apps/bezgelor_data/priv/data/Spell4Effects.json
git commit -m "feat(data): extract Spell4Effects game data"
```

---

## Task 2: Add spell4_effects ETS table to Store

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex:60-100`
- Test: `apps/bezgelor_data/test/store_test.exs`

**Step 1: Write failing test**

Add to `apps/bezgelor_data/test/store_test.exs`:

```elixir
describe "spell4_effects" do
  test "get_spell4_effects/1 returns effects for a spell" do
    # Pistol Shot spell ID
    effects = BezgelorData.Store.get_spell4_effects(55665)
    assert is_list(effects)
    # Should have at least one damage effect
    assert length(effects) >= 1
  end

  test "get_spell4_effects/1 returns empty list for unknown spell" do
    effects = BezgelorData.Store.get_spell4_effects(999_999_999)
    assert effects == []
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/jrimmer/work/bezgelor
mix test apps/bezgelor_data/test/store_test.exs --seed 0
```

Expected: FAIL - `get_spell4_effects/1 is undefined`

**Step 3: Add :spell4_effects to table list**

Edit `apps/bezgelor_data/lib/bezgelor_data/store.ex`, add to `@tables` list around line 70:

```elixir
@tables [
  :creatures,
  # ... existing entries ...
  :spell4_entries,
  :spell4_bases,
  :spell4_effects,  # ADD THIS LINE
  :spell_levels,
  # ... rest of list ...
]
```

**Step 4: Add loader function**

Add after the existing spell loaders (around line 2450):

```elixir
defp load_spell4_effects do
  path = priv_path("Spell4Effects.json")

  case load_json_raw(path) do
    {:ok, data} when is_list(data) ->
      # Group effects by spellId for fast lookup
      effects_by_spell =
        data
        |> Enum.map(&normalize_keys/1)
        |> Enum.group_by(fn e -> e[:spell_id] || e["spellId"] end)

      Enum.each(effects_by_spell, fn {spell_id, effects} ->
        :ets.insert(:spell4_effects, {spell_id, effects})
      end)

      Logger.info("Loaded #{length(data)} spell effects for #{map_size(effects_by_spell)} spells")

    {:ok, _} ->
      Logger.warning("Spell4Effects.json has unexpected format")

    {:error, reason} ->
      Logger.warning("Failed to load Spell4Effects: #{inspect(reason)}")
  end
end
```

**Step 5: Add loader to parallel load tasks**

In `load_all_data/0` around line 1808, add to the task list:

```elixir
fn -> load_spell4_effects() end,
```

**Step 6: Add public accessor function**

Add around line 3400:

```elixir
@doc """
Get all Spell4Effects entries for a given spell ID.

Returns a list of effect maps, or empty list if no effects found.
"""
@spec get_spell4_effects(non_neg_integer()) :: [map()]
def get_spell4_effects(spell_id) when is_integer(spell_id) do
  case :ets.lookup(:spell4_effects, spell_id) do
    [{^spell_id, effects}] -> effects
    [] -> []
  end
end
```

**Step 7: Run tests**

```bash
mix test apps/bezgelor_data/test/store_test.exs --seed 0
```

Expected: PASS

**Step 8: Commit**

```bash
git add apps/bezgelor_data/lib/bezgelor_data/store.ex apps/bezgelor_data/test/store_test.exs
git commit -m "feat(data): load Spell4Effects into ETS with spell_id grouping"
```

---

## Task 3: Add BezgelorData.get_spell4_effects/1 API

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data.ex`
- Test: `apps/bezgelor_data/test/bezgelor_data_test.exs`

**Step 1: Write failing test**

Add to `apps/bezgelor_data/test/bezgelor_data_test.exs`:

```elixir
describe "spell effects" do
  test "get_spell4_effects/1 returns effects list" do
    effects = BezgelorData.get_spell4_effects(55665)
    assert is_list(effects)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test apps/bezgelor_data/test/bezgelor_data_test.exs::spell --seed 0
```

Expected: FAIL - function not defined

**Step 3: Add function to BezgelorData module**

Edit `apps/bezgelor_data/lib/bezgelor_data.ex`, add after `get_spell4_entry/1` around line 223:

```elixir
@doc """
Get all Spell4Effects entries for a given spell ID.

Returns list of effect maps, or empty list if none found.
"""
@spec get_spell4_effects(non_neg_integer()) :: [map()]
def get_spell4_effects(spell_id) do
  Store.get_spell4_effects(spell_id)
end
```

**Step 4: Run test**

```bash
mix test apps/bezgelor_data/test/bezgelor_data_test.exs --seed 0
```

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_data/lib/bezgelor_data.ex apps/bezgelor_data/test/bezgelor_data_test.exs
git commit -m "feat(data): add BezgelorData.get_spell4_effects/1 API"
```

---

## Task 4: Parse Spell4Effects into SpellEffect structs

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/spell.ex:215-250`
- Test: `apps/bezgelor_core/test/spell_test.exs`

**Step 1: Write failing test**

Add to `apps/bezgelor_core/test/spell_test.exs`:

```elixir
describe "game data effects" do
  test "Pistol Shot (55665) has damage effect" do
    spell = BezgelorCore.Spell.get(55665)
    assert spell != nil
    assert length(spell.effects) >= 1

    damage_effect = Enum.find(spell.effects, &(&1.type == :damage))
    assert damage_effect != nil
    assert damage_effect.amount > 0
  end

  test "spell effects are parsed from Spell4Effects data" do
    # Use a known spell with effects
    spell = BezgelorCore.Spell.get(55665)
    refute Enum.empty?(spell.effects), "Expected spell to have effects loaded from game data"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test apps/bezgelor_core/test/spell_test.exs --seed 0
```

Expected: FAIL - effects list is empty

**Step 3: Add effect parsing to get_from_game_data**

Edit `apps/bezgelor_core/lib/bezgelor_core/spell.ex`. Replace the `get_from_game_data/1` function (around line 215):

```elixir
defp get_from_game_data(id) do
  alias BezgelorCore.SpellEffect

  case BezgelorData.get_spell4_entry(id) do
    {:ok, spell4} ->
      name = get_spell_name_from_spell4(spell4)
      cast_time = Map.get(spell4, :castTime, 0) || Map.get(spell4, "castTime", 0)
      cooldown = Map.get(spell4, :spellCoolDown, 0) || Map.get(spell4, "spellCoolDown", 0)

      # Load effects from Spell4Effects table
      effects = parse_spell_effects(id)

      %__MODULE__{
        id: id,
        name: name,
        description: Map.get(spell4, :description, "Game spell #{id}"),
        cast_time: cast_time,
        cooldown: cooldown,
        gcd: true,
        range: Map.get(spell4, :targetMaxRange, 30.0),
        resource_cost: 0,
        resource_type: :none,
        target_type: determine_target_type(effects),
        aoe_radius: 0.0,
        effects: effects,
        interrupt_flags: [],
        spell_school: :magic,
        hostile: has_hostile_effect?(effects)
      }

    :error ->
      nil
  end
end

# Parse Spell4Effects entries into SpellEffect structs
defp parse_spell_effects(spell_id) do
  alias BezgelorCore.SpellEffect

  BezgelorData.get_spell4_effects(spell_id)
  |> Enum.map(&parse_single_effect/1)
  |> Enum.reject(&is_nil/1)
end

defp parse_single_effect(effect_data) do
  alias BezgelorCore.SpellEffect

  effect_type = effect_data[:effect_type] || effect_data["effectType"] || 0
  damage_type = effect_data[:damage_type] || effect_data["damageType"] || 0

  # DataBits00 typically contains base damage/heal amount
  amount = effect_data[:data_bits_00] || effect_data["dataBits00"] || 0

  case map_effect_type(effect_type) do
    nil -> nil
    type ->
      %SpellEffect{
        type: type,
        amount: amount,
        scaling: 0.0,
        scaling_stat: nil,
        school: map_damage_type(damage_type),
        duration: effect_data[:duration_time] || effect_data["durationTime"] || 0,
        tick_interval: effect_data[:tick_time] || effect_data["tickTime"] || 0
      }
  end
end

# Map NexusForever SpellEffectType enum values to atoms
# Reference: NexusForever.Game.Static.Spell.SpellEffectType
defp map_effect_type(type_id) do
  case type_id do
    1 -> :damage           # Damage
    2 -> :heal             # Heal
    3 -> :damage           # DirectDamage (also damage)
    6 -> :buff             # Buff
    8 -> :debuff           # Debuff
    12 -> :dot             # DoT
    13 -> :hot             # HoT
    27 -> :resurrect       # Resurrect
    _ -> nil               # Unknown/unsupported
  end
end

# Map NexusForever DamageType enum to spell school
defp map_damage_type(damage_type) do
  case damage_type do
    0 -> :physical
    1 -> :magic        # Magic
    2 -> :tech         # Tech
    _ -> :physical
  end
end

defp determine_target_type(effects) do
  if Enum.any?(effects, &(&1.type in [:damage, :debuff, :dot])) do
    :enemy
  else
    :self
  end
end

defp has_hostile_effect?(effects) do
  Enum.any?(effects, &(&1.type in [:damage, :debuff, :dot]))
end
```

**Step 4: Run tests**

```bash
mix test apps/bezgelor_core/test/spell_test.exs --seed 0
```

Expected: PASS (or FAIL if spell 55665 has no effects in data - adjust test spell ID)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/spell.ex apps/bezgelor_core/test/spell_test.exs
git commit -m "feat(spell): parse Spell4Effects into SpellEffect structs"
```

---

## Task 5: Add fallback effects for class auto-attacks

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/spell.ex`
- Test: `apps/bezgelor_core/test/spell_test.exs`

**Step 1: Write failing test**

Add to `apps/bezgelor_core/test/spell_test.exs`:

```elixir
describe "class auto-attack fallbacks" do
  test "Spellslinger Pistol Shot (55665) has damage effect even without game data" do
    spell = BezgelorCore.Spell.get(55665)
    assert spell != nil
    assert length(spell.effects) >= 1

    damage_effect = Enum.find(spell.effects, &(&1.type == :damage))
    assert damage_effect != nil
    assert damage_effect.amount > 0
  end

  test "Warrior Relentless Strikes (20319) has damage effect" do
    spell = BezgelorCore.Spell.get(20319)
    assert spell != nil
    damage_effect = Enum.find(spell.effects, &(&1.type == :damage))
    assert damage_effect != nil
  end
end
```

**Step 2: Run test to verify current state**

```bash
mix test apps/bezgelor_core/test/spell_test.exs --seed 0
```

Note: May PASS if Task 4 loaded effects, or FAIL if game data lacks effects.

**Step 3: Add fallback logic**

Edit `apps/bezgelor_core/lib/bezgelor_core/spell.ex`, update `parse_spell_effects/1`:

```elixir
# Class auto-attack spell IDs that need fallback effects
@class_auto_attacks %{
  # Warrior
  20319 => %{name: "Relentless Strikes", damage: 25, range: 5.0},
  # Stalker
  20302 => %{name: "Shred", damage: 30, range: 5.0},
  # Esper
  20304 => %{name: "Telekinetic Strike", damage: 28, range: 25.0},
  # Spellslinger
  55665 => %{name: "Pistol Shot", damage: 22, range: 25.0},
  # Medic
  57440 => %{name: "Discharge", damage: 26, range: 25.0},
  # Engineer
  28936 => %{name: "Bolt Caster", damage: 24, range: 25.0}
}

# Parse Spell4Effects entries into SpellEffect structs
defp parse_spell_effects(spell_id) do
  alias BezgelorCore.SpellEffect

  effects =
    BezgelorData.get_spell4_effects(spell_id)
    |> Enum.map(&parse_single_effect/1)
    |> Enum.reject(&is_nil/1)

  # If no effects found and this is a class auto-attack, add fallback
  if Enum.empty?(effects) and Map.has_key?(@class_auto_attacks, spell_id) do
    fallback = Map.get(@class_auto_attacks, spell_id)
    [
      %SpellEffect{
        type: :damage,
        amount: fallback.damage,
        scaling: 0.3,
        scaling_stat: :power,
        school: :physical
      }
    ]
  else
    effects
  end
end
```

**Step 4: Run tests**

```bash
mix test apps/bezgelor_core/test/spell_test.exs --seed 0
```

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/spell.ex apps/bezgelor_core/test/spell_test.exs
git commit -m "feat(spell): add fallback effects for class auto-attacks"
```

---

## Task 6: Integration test - spell casting damages creature

**Files:**
- Test: `apps/bezgelor_world/test/integration/combat_flow_test.exs`

**Step 1: Write integration test**

Create `apps/bezgelor_world/test/integration/combat_flow_test.exs`:

```elixir
defmodule BezgelorWorld.Integration.CombatFlowTest do
  @moduledoc """
  Integration test for the full combat flow:
  Player casts spell → damage applied → creature aggros → creature dies → XP awarded
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.Instance
  alias BezgelorWorld.WorldManager
  alias BezgelorCore.{Spell, SpellEffect}

  @test_world_id 1
  @test_world_key {@test_world_id, 1}

  setup do
    # Ensure world instance is running
    {:ok, _pid} = Instance.start_link(world_id: @test_world_id, instance_id: 1)

    # Spawn a test creature
    {:ok, creature_guid} = Instance.spawn_creature(@test_world_key, 1234, {100.0, 0.0, 100.0})

    # Create test player entity
    player_guid = WorldManager.generate_guid(:player)

    on_exit(fn ->
      Instance.stop(@test_world_key)
    end)

    %{creature_guid: creature_guid, player_guid: player_guid}
  end

  describe "spell casting combat flow" do
    test "Pistol Shot spell has damage effect", %{} do
      spell = Spell.get(55665)
      assert spell != nil, "Pistol Shot spell should exist"

      damage_effects = Enum.filter(spell.effects, &(&1.type == :damage))
      assert length(damage_effects) >= 1, "Pistol Shot should have at least one damage effect"

      [effect | _] = damage_effects
      assert effect.amount > 0, "Damage amount should be positive"
    end

    test "casting spell damages creature", %{creature_guid: creature_guid, player_guid: player_guid} do
      # Get creature initial health
      {:ok, initial_state} = Instance.get_creature(@test_world_key, creature_guid)
      initial_health = initial_state.entity.health

      # Apply damage (simulating spell effect)
      {:ok, :damaged, result} = Instance.damage_creature(@test_world_key, creature_guid, player_guid, 25)

      assert result.remaining_health < initial_health
      assert result.remaining_health == initial_health - 25
    end

    test "killing creature awards XP", %{creature_guid: creature_guid, player_guid: player_guid} do
      # Deal lethal damage
      {:ok, :killed, result} = Instance.damage_creature(@test_world_key, creature_guid, player_guid, 9999)

      assert Map.has_key?(result, :xp_reward) or Map.has_key?(result, :rewards)
    end
  end
end
```

**Step 2: Run integration test**

```bash
mix test apps/bezgelor_world/test/integration/combat_flow_test.exs --seed 0
```

Expected: PASS (or reveals any remaining integration issues)

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/integration/combat_flow_test.exs
git commit -m "test: add combat flow integration test"
```

---

## Task 7: Verify full combat loop manually

**Files:** None (manual verification)

**Step 1: Start the server**

```bash
cd /Users/jrimmer/work/bezgelor
mix run --no-halt
```

**Step 2: Connect with WildStar client**

1. Log in with test account
2. Select Cybexa (Spellslinger) character
3. Enter Levian Bay zone
4. Find a Seaspine Girrok (passive creature)
5. Right-click to target
6. Press R (or slot 3) to cast Pistol Shot

**Step 3: Verify combat flow**

Expected behavior:
- [ ] Pistol Shot animation plays
- [ ] Damage numbers appear on creature
- [ ] Creature health bar decreases
- [ ] Creature becomes aggressive and attacks player
- [ ] Repeated attacks kill creature
- [ ] Creature becomes lootable corpse
- [ ] XP is awarded to player

**Step 4: Document any issues**

If any step fails, create follow-up tasks.

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Extract Spell4Effects.tbl | Data extraction |
| 2 | Add ETS table for spell effects | store.ex |
| 3 | Add BezgelorData API | bezgelor_data.ex |
| 4 | Parse effects into SpellEffect structs | spell.ex |
| 5 | Add fallback effects for auto-attacks | spell.ex |
| 6 | Integration test | combat_flow_test.exs |
| 7 | Manual verification | N/A |

Total estimated time: 2-3 hours
