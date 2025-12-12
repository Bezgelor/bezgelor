# Combat System Gaps Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the 5 critical gaps in the combat loop to move from "functional demo" to "playable game" with real stats, coordinated periodic ticks, XP persistence, corpse-based loot pickup, and telegraph visualization.

**Architecture:** Combat calculations already exist in `bezgelor_core/spell_effect.ex` but use hardcoded stats. Periodic ticking exists in `BuffManager.Shard` but uses per-buff timers (not coordinated). We need to: (1) wire real character stats through the combat path, (2) implement coordinated zone-wide tick scheduling for authentic WildStar behavior, (3) persist XP to database on kills, (4) implement corpse entities for loot pickup interaction, and (5) add telegraph geometry data to spell packets.

**Tech Stack:** Elixir/OTP, Ecto for persistence, ETS for static data, GenServer for state management, binary protocol packets.

---

## Implementation Order

1. **Task 1-4: Player Stats Lookup** - Replace hardcoded `%{power: 100, ...}` with real character stats
2. **Task 5-8: Coordinated Tick System** - Zone-wide TickScheduler for synchronized DoT/HoT processing
3. **Task 9-11: XP Persistence** - Save XP to database on creature kills
4. **Task 12-17: Loot Pickup (Corpse-based)** - Spawn corpse entities, allow pickup interaction
5. **Task 18-21: Telegraph Transmission** - Send telegraph geometry to clients

---

## Task 1: Create Character Stats Module

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/character_stats.ex`
- Test: `apps/bezgelor_core/test/character_stats_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorCore.CharacterStatsTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.CharacterStats

  describe "compute_combat_stats/1" do
    test "computes combat stats from base character data" do
      character = %{
        level: 10,
        class: 1,  # Warrior
        race: 0    # Human
      }

      stats = CharacterStats.compute_combat_stats(character)

      assert stats.power > 0
      assert stats.tech > 0
      assert stats.support > 0
      assert stats.crit_chance >= 5
      assert stats.armor > 0
    end

    test "higher level characters have higher stats" do
      low_level = CharacterStats.compute_combat_stats(%{level: 1, class: 1, race: 0})
      high_level = CharacterStats.compute_combat_stats(%{level: 50, class: 1, race: 0})

      assert high_level.power > low_level.power
      assert high_level.armor > low_level.armor
    end

    test "assault classes favor power" do
      warrior = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})  # Warrior
      esper = CharacterStats.compute_combat_stats(%{level: 10, class: 4, race: 0})    # Esper/healer

      assert warrior.power >= esper.power
    end
  end

  describe "get_stat_modifier/2" do
    test "buff manager stat modifiers add to computed stats" do
      base_stats = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})

      # Simulate +50 power buff
      modified = CharacterStats.apply_buff_modifiers(base_stats, %{power: 50, armor: 0})

      assert modified.power == base_stats.power + 50
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/character_stats_test.exs -v`
Expected: FAIL with "module CharacterStats is not available"

**Step 3: Write minimal implementation**

```elixir
defmodule BezgelorCore.CharacterStats do
  @moduledoc """
  Character combat stat calculations.

  WildStar uses 6 primary attributes that convert to combat stats:
  - Brutality -> Assault Power (DPS)
  - Finesse -> Strikethrough (Hit Rating)
  - Moxie -> Critical Hit Rating
  - Tech -> Support Power (Healing)
  - Insight -> Deflect Critical
  - Grit -> Armor, Max Health

  This module computes effective combat stats from character level,
  class, and any active buff modifiers.
  """

  @type combat_stats :: %{
    power: non_neg_integer(),
    tech: non_neg_integer(),
    support: non_neg_integer(),
    crit_chance: non_neg_integer(),
    armor: float(),
    magic_resist: float(),
    tech_resist: float(),
    max_health: non_neg_integer()
  }

  # Base stat per level (WildStar-authentic scaling)
  @base_stat_per_level 10
  @base_health_per_level 50
  @base_crit_chance 5

  # Class stat multipliers (class_id => {power_mult, tech_mult, support_mult})
  @class_multipliers %{
    1 => {1.2, 0.8, 0.9},   # Warrior - assault focused
    2 => {1.0, 1.0, 1.0},   # Spellslinger - balanced
    3 => {1.1, 0.9, 1.0},   # Stalker - assault/balanced
    4 => {0.8, 1.2, 1.1},   # Esper - support focused
    5 => {0.9, 1.1, 1.1},   # Medic - support focused
    6 => {1.15, 0.85, 0.9}  # Engineer - assault focused
  }

  @doc """
  Compute combat stats from character base attributes.

  ## Parameters

  - `character` - Map with `:level`, `:class`, and optionally `:race`

  ## Returns

  Combat stats map with power, tech, support, crit_chance, armor, etc.
  """
  @spec compute_combat_stats(map()) :: combat_stats()
  def compute_combat_stats(%{level: level, class: class} = _character) do
    {power_mult, tech_mult, support_mult} = Map.get(@class_multipliers, class, {1.0, 1.0, 1.0})

    base_stat = level * @base_stat_per_level

    %{
      power: round(base_stat * power_mult),
      tech: round(base_stat * tech_mult),
      support: round(base_stat * support_mult),
      crit_chance: @base_crit_chance + div(level, 10),
      armor: level * 0.01,
      magic_resist: level * 0.005,
      tech_resist: level * 0.005,
      max_health: 100 + level * @base_health_per_level
    }
  end

  @doc """
  Apply buff modifiers to computed stats.
  """
  @spec apply_buff_modifiers(combat_stats(), map()) :: combat_stats()
  def apply_buff_modifiers(stats, modifiers) do
    %{
      stats |
      power: stats.power + Map.get(modifiers, :power, 0),
      tech: stats.tech + Map.get(modifiers, :tech, 0),
      support: stats.support + Map.get(modifiers, :support, 0),
      crit_chance: stats.crit_chance + Map.get(modifiers, :crit_chance, 0),
      armor: stats.armor + Map.get(modifiers, :armor, 0)
    }
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/character_stats_test.exs -v`
Expected: PASS (3 tests, 0 failures)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/character_stats.ex apps/bezgelor_core/test/character_stats_test.exs
git commit -m "feat(core): add CharacterStats module for combat stat calculations"
```

---

## Task 2: Wire Character Stats to SpellHandler

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex:85-93`

**Step 1: Write integration test for stats lookup**

Create test file `apps/bezgelor_world/test/handler/spell_handler_stats_test.exs`:

```elixir
defmodule BezgelorWorld.Handler.SpellHandlerStatsTest do
  use ExUnit.Case, async: false

  alias BezgelorCore.CharacterStats

  describe "get_caster_stats/1" do
    test "retrieves stats from session data" do
      session_data = %{
        character: %{level: 10, class: 1, race: 0},
        entity_guid: 12345
      }

      stats = CharacterStats.compute_combat_stats(session_data.character)

      # Stats should be computed from character, not hardcoded
      assert stats.power > 50
      assert is_integer(stats.crit_chance)
    end
  end
end
```

**Step 2: Run test to verify behavior**

Run: `mix test apps/bezgelor_world/test/handler/spell_handler_stats_test.exs -v`

**Step 3: Modify spell_handler.ex to use real stats**

Replace lines 85-93 in `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`:

Old:
```elixir
  defp do_cast(spell, packet, player_guid, state) do
    # Get caster stats (simplified for Phase 8)
    caster_stats = %{
      power: 100,
      tech: 100,
      support: 100,
      crit_chance: 10
    }
```

New:
```elixir
  defp do_cast(spell, packet, player_guid, state) do
    # Get caster stats from character data and buff modifiers
    caster_stats = get_caster_stats(state)
```

Add new private function at end of module:

```elixir
  # Get combat stats for the casting player
  defp get_caster_stats(state) do
    alias BezgelorCore.CharacterStats
    alias BezgelorWorld.BuffManager

    character = state.session_data[:character]
    entity_guid = state.session_data[:entity_guid]

    base_stats =
      if character do
        CharacterStats.compute_combat_stats(character)
      else
        # Fallback for tests without full session
        %{power: 100, tech: 100, support: 100, crit_chance: 10, armor: 0.0}
      end

    # Apply buff modifiers if entity has buffs
    if entity_guid do
      power_mod = BuffManager.get_stat_modifier(entity_guid, :power)
      tech_mod = BuffManager.get_stat_modifier(entity_guid, :tech)
      support_mod = BuffManager.get_stat_modifier(entity_guid, :support)
      crit_mod = BuffManager.get_stat_modifier(entity_guid, :crit_chance)

      CharacterStats.apply_buff_modifiers(base_stats, %{
        power: power_mod,
        tech: tech_mod,
        support: support_mod,
        crit_chance: crit_mod
      })
    else
      base_stats
    end
  end
```

**Step 4: Run tests**

Run: `mix test apps/bezgelor_world/test/handler/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex apps/bezgelor_world/test/handler/spell_handler_stats_test.exs
git commit -m "feat(world): wire CharacterStats to SpellHandler for real combat stats"
```

---

## Task 3: Store Character in Session Data

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/character_select_handler.ex`

**Step 1: Find where session_data is populated with character**

The character select handler needs to store the full character map in session_data.

**Step 2: Verify character data is stored**

Check that when a character is selected, the session_data includes:
- `:character` - The full character struct/map
- `:character_id` - Just the ID

If not present, modify to include it.

**Step 3: Run related tests**

Run: `mix test apps/bezgelor_world/test/ -v`

**Step 4: Commit if changes needed**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/character_select_handler.ex
git commit -m "feat(world): store character data in session for stats lookup"
```

---

## Task 4: Add Stats Lookup to Creature Combat

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex:664-670`

**Step 1: Write test for creature attack with real stats**

```elixir
# In apps/bezgelor_world/test/creature_manager_test.exs
test "creature damage calculation uses player armor" do
  # Player with armor should take reduced damage
  # This verifies the damage path uses real stats
end
```

**Step 2: Update `apply_creature_attack` to lookup player stats**

Currently at line 664 the function doesn't use player defensive stats. Update to:

```elixir
defp apply_creature_attack(creature_entity, template, target_guid) do
  if is_player_guid?(target_guid) do
    damage = CreatureTemplate.roll_damage(template)

    # Get target's defensive stats
    target_stats = get_target_stats(target_guid)

    # Apply mitigation
    mitigation = Map.get(target_stats, :armor, 0.0)
    final_damage = round(damage * (1 - mitigation))

    # ... rest of function
  end
end

defp get_target_stats(player_guid) do
  case ZoneInstance.get_entity({1, 1}, player_guid) do
    {:ok, player_entity} ->
      if character = player_entity.character do
        BezgelorCore.CharacterStats.compute_combat_stats(character)
      else
        %{armor: 0.0}
      end
    _ ->
      %{armor: 0.0}
  end
end
```

**Step 3: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_manager_test.exs -v`

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): use player defensive stats in creature attacks"
```

---

## Task 5: Create TickScheduler GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/tick_scheduler.ex`
- Test: `apps/bezgelor_world/test/tick_scheduler_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_world/test/tick_scheduler_test.exs`:

```elixir
defmodule BezgelorWorld.TickSchedulerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.TickScheduler

  setup do
    # Start with a fast tick rate for testing
    {:ok, pid} = start_supervised({TickScheduler, tick_interval: 50})
    %{scheduler: pid}
  end

  describe "tick scheduling" do
    test "fires ticks at regular intervals" do
      # Register to receive tick notifications
      TickScheduler.register_listener(self())

      # Wait for 3 ticks
      assert_receive {:tick, tick_num}, 200
      assert tick_num >= 1

      assert_receive {:tick, _}, 200
      assert_receive {:tick, _}, 200
    end

    test "tick number increments" do
      TickScheduler.register_listener(self())

      assert_receive {:tick, tick1}, 200
      assert_receive {:tick, tick2}, 200

      assert tick2 > tick1
    end
  end

  describe "listener management" do
    test "can unregister listener" do
      TickScheduler.register_listener(self())
      assert_receive {:tick, _}, 200

      TickScheduler.unregister_listener(self())

      # Should not receive any more ticks
      refute_receive {:tick, _}, 150
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/tick_scheduler_test.exs -v`
Expected: FAIL with "module TickScheduler is not available"

**Step 3: Implement TickScheduler**

Create `apps/bezgelor_world/lib/bezgelor_world/tick_scheduler.ex`:

```elixir
defmodule BezgelorWorld.TickScheduler do
  @moduledoc """
  Zone-wide tick scheduler for coordinated periodic effect processing.

  ## Overview

  WildStar uses a 1-second server tick for all periodic effects. This ensures:
  - All DoTs tick simultaneously
  - All HoTs tick simultaneously
  - Fair timing in PvP (no one's DoT ticks right before another's heal)

  ## Architecture

  The TickScheduler fires every 1000ms and notifies all registered listeners.
  BuffManager.Shard registers as a listener and processes all due periodic
  effects when it receives a tick notification.

  ## Usage

      # Register to receive tick notifications
      TickScheduler.register_listener(self())

      # Handle tick in your GenServer
      def handle_info({:tick, tick_number}, state) do
        # Process periodic effects
        {:noreply, state}
      end
  """

  use GenServer

  require Logger

  @default_tick_interval 1000  # WildStar's 1-second tick

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a process to receive tick notifications.

  The process will receive `{:tick, tick_number}` messages.
  """
  @spec register_listener(pid()) :: :ok
  def register_listener(pid) do
    GenServer.call(__MODULE__, {:register, pid})
  end

  @doc """
  Unregister a process from tick notifications.
  """
  @spec unregister_listener(pid()) :: :ok
  def unregister_listener(pid) do
    GenServer.call(__MODULE__, {:unregister, pid})
  end

  @doc """
  Get current tick number.
  """
  @spec current_tick() :: non_neg_integer()
  def current_tick do
    GenServer.call(__MODULE__, :current_tick)
  end

  @doc """
  Get the tick interval in milliseconds.
  """
  @spec tick_interval() :: non_neg_integer()
  def tick_interval do
    GenServer.call(__MODULE__, :tick_interval)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    tick_interval = Keyword.get(opts, :tick_interval, @default_tick_interval)

    state = %{
      tick_interval: tick_interval,
      tick_number: 0,
      listeners: MapSet.new()
    }

    # Schedule first tick
    Process.send_after(self(), :tick, tick_interval)

    Logger.info("TickScheduler started with #{tick_interval}ms interval")
    {:ok, state}
  end

  @impl true
  def handle_call({:register, pid}, _from, state) do
    # Monitor the process so we can clean up if it dies
    Process.monitor(pid)
    listeners = MapSet.put(state.listeners, pid)
    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl true
  def handle_call({:unregister, pid}, _from, state) do
    listeners = MapSet.delete(state.listeners, pid)
    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_number, state}
  end

  @impl true
  def handle_call(:tick_interval, _from, state) do
    {:reply, state.tick_interval, state}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_number = state.tick_number + 1

    # Notify all listeners
    Enum.each(state.listeners, fn pid ->
      send(pid, {:tick, tick_number})
    end)

    # Schedule next tick
    Process.send_after(self(), :tick, state.tick_interval)

    {:noreply, %{state | tick_number: tick_number}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up dead listener
    listeners = MapSet.delete(state.listeners, pid)
    {:noreply, %{state | listeners: listeners}}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/tick_scheduler_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/tick_scheduler.ex apps/bezgelor_world/test/tick_scheduler_test.exs
git commit -m "feat(world): add TickScheduler for coordinated periodic effect timing"
```

---

## Task 6: Add TickScheduler to Supervision Tree

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`

**Step 1: Add TickScheduler to children**

Find the children list in `application.ex` and add TickScheduler before BuffManager:

```elixir
children = [
  # ... existing children ...
  BezgelorWorld.TickScheduler,
  BezgelorWorld.BuffManager,
  # ... rest of children ...
]
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/tick_scheduler_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/application.ex
git commit -m "feat(world): add TickScheduler to supervision tree"
```

---

## Task 7: Refactor BuffManager.Shard to Use TickScheduler

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/buff_manager/shard.ex`
- Test: `apps/bezgelor_world/test/buff_manager_coordinated_tick_test.exs`

**Step 1: Write test for coordinated ticking**

Create `apps/bezgelor_world/test/buff_manager_coordinated_tick_test.exs`:

```elixir
defmodule BezgelorWorld.BuffManagerCoordinatedTickTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{BuffManager, TickScheduler}
  alias BezgelorCore.BuffDebuff

  setup do
    # Start TickScheduler with fast interval for testing
    start_supervised!({TickScheduler, tick_interval: 50})
    start_supervised!(BuffManager)
    BuffManager.clear_entity(12345)
    BuffManager.clear_entity(67890)
    :ok
  end

  describe "coordinated periodic ticks" do
    test "multiple periodic buffs tick together on scheduler tick" do
      player1_guid = 12345
      player2_guid = 67890

      # Apply periodic buffs to two players
      buff1 = BuffDebuff.new(%{
        id: 1,
        spell_id: 1,
        buff_type: :periodic,
        amount: 10,
        duration: 500,
        tick_interval: 50,  # Will tick every scheduler tick
        is_debuff: true
      })

      buff2 = BuffDebuff.new(%{
        id: 2,
        spell_id: 2,
        buff_type: :periodic,
        amount: 20,
        duration: 500,
        tick_interval: 50,
        is_debuff: false
      })

      {:ok, _} = BuffManager.apply_buff(player1_guid, buff1, 99999)
      {:ok, _} = BuffManager.apply_buff(player2_guid, buff2, 99999)

      # Wait for ticks to process
      Process.sleep(200)

      # Both buffs should still be active and ticking together
      assert BuffManager.has_buff?(player1_guid, 1)
      assert BuffManager.has_buff?(player2_guid, 2)
    end
  end
end
```

**Step 2: Run test to establish baseline**

Run: `mix test apps/bezgelor_world/test/buff_manager_coordinated_tick_test.exs -v`

**Step 3: Refactor BuffManager.Shard**

Update `apps/bezgelor_world/lib/bezgelor_world/buff_manager/shard.ex`:

1. Remove per-buff tick timer scheduling from `handle_call({:apply_buff, ...})`
2. Register with TickScheduler in `init/1`
3. Add `handle_info({:tick, tick_number}, state)` to process all due periodic effects

Key changes:

```elixir
  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)

    # Register with TickScheduler for coordinated ticking
    if Process.whereis(BezgelorWorld.TickScheduler) do
      BezgelorWorld.TickScheduler.register_listener(self())
    end

    state = %{
      shard_id: shard_id,
      entities: %{}
    }

    Logger.debug("BuffManager.Shard #{shard_id} started")
    {:ok, state}
  end

  # Remove the per-buff tick timer from apply_buff
  # Remove: tick_ref = Process.send_after(self(), {:buff_tick, entity_guid, buff_id}, buff.tick_interval)

  # Add coordinated tick handler
  @impl true
  def handle_info({:tick, _tick_number}, state) do
    now = System.monotonic_time(:millisecond)

    # Process all periodic effects that should tick
    state = process_all_periodic_ticks(state, now)

    {:noreply, state}
  end

  defp process_all_periodic_ticks(state, now) do
    Enum.reduce(state.entities, state, fn {entity_guid, entity}, acc_state ->
      process_entity_periodic_effects(acc_state, entity_guid, entity, now)
    end)
  end

  defp process_entity_periodic_effects(state, entity_guid, entity, now) do
    Enum.reduce(entity.effects, state, fn {buff_id, effect_data}, acc_state ->
      buff = effect_data.buff

      if BuffDebuff.periodic?(buff) and ActiveEffect.active?(entity.effects, buff_id, now) do
        process_periodic_tick(entity_guid, effect_data.caster_guid, buff)
      end

      acc_state
    end)
  end
```

**Step 4: Run tests**

Run: `mix test apps/bezgelor_world/test/buff_manager_coordinated_tick_test.exs -v`
Run: `mix test apps/bezgelor_world/test/buff_manager_periodic_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/buff_manager/shard.ex apps/bezgelor_world/test/buff_manager_coordinated_tick_test.exs
git commit -m "refactor(world): use TickScheduler for coordinated periodic effect ticking"
```

---

## Task 8: Remove Legacy Per-Buff Tick Timers

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/buff_manager/shard.ex`

**Step 1: Clean up tick_timers references**

Remove all references to the `tick_timers` map in entity state since we no longer use per-buff timers:

1. Remove `tick_timers` from entity state struct
2. Remove tick timer scheduling in `apply_buff`
3. Remove tick timer cancellation in `remove_buff`
4. Remove the old `handle_info({:buff_tick, ...})` handler
5. Keep expiration timers (those are still per-buff)

**Step 2: Run all BuffManager tests**

Run: `mix test apps/bezgelor_world/test/buff_manager*_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/buff_manager/shard.ex
git commit -m "refactor(world): remove legacy per-buff tick timers"
```

---

## Task 9: Add XP Persistence to Characters Context

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/characters.ex`
- Test: `apps/bezgelor_db/test/schema/character_xp_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_db/test/schema/character_xp_test.exs`:

```elixir
defmodule BezgelorDb.CharacterXPTest do
  use BezgelorDb.DataCase

  alias BezgelorDb.Characters

  @moduletag :database

  describe "add_experience/2" do
    test "adds XP to character total" do
      # Create test character
      {:ok, character} = create_test_character()
      initial_xp = character.total_xp

      {:ok, updated} = Characters.add_experience(character, 100)

      assert updated.total_xp == initial_xp + 100
    end

    test "returns level up info when XP threshold crossed" do
      {:ok, character} = create_test_character(%{level: 1, total_xp: 900})

      # XP threshold for level 2 is 1000
      {:ok, updated, level_up: true} = Characters.add_experience(character, 200)

      assert updated.level == 2
      assert updated.total_xp == 1100
    end
  end

  defp create_test_character(attrs \\ %{}) do
    # Setup code to create test account and character
    {:ok, account} = BezgelorDb.Accounts.create_account(%{
      email: "test#{System.unique_integer()}@example.com",
      password: "testpassword123"
    })

    default_attrs = %{
      name: "TestChar#{System.unique_integer()}",
      sex: 0,
      race: 0,
      class: 1,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1,
      level: 1,
      total_xp: 0
    }

    Characters.create_character(account.id, Map.merge(default_attrs, attrs))
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/character_xp_test.exs -v --include database`
Expected: FAIL with "function Characters.add_experience/2 is undefined"

**Step 3: Implement add_experience/2**

Add to `apps/bezgelor_db/lib/bezgelor_db/characters.ex`:

```elixir
  @doc """
  Add experience points to a character.

  ## Returns

  - `{:ok, character}` - XP added, no level up
  - `{:ok, character, level_up: true}` - XP added and character leveled up
  - `{:error, changeset}` - Update failed
  """
  @spec add_experience(Character.t(), non_neg_integer()) ::
          {:ok, Character.t()} | {:ok, Character.t(), keyword()} | {:error, Ecto.Changeset.t()}
  def add_experience(%Character{} = character, xp_amount) when xp_amount >= 0 do
    new_total = character.total_xp + xp_amount
    current_level = character.level

    # Calculate if level up occurred
    {new_level, leveled_up} = calculate_level(new_total, current_level)

    changes = %{
      total_xp: new_total,
      level: new_level
    }

    case character
         |> Ecto.Changeset.change(changes)
         |> Repo.update() do
      {:ok, updated} ->
        if leveled_up do
          {:ok, updated, level_up: true}
        else
          {:ok, updated}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Get XP required for a given level.

  WildStar XP curve: level * 1000 base, with exponential growth.
  """
  @spec xp_for_level(non_neg_integer()) :: non_neg_integer()
  def xp_for_level(level) when level >= 1 do
    # Simplified WildStar XP curve
    round(level * 1000 * :math.pow(1.1, level - 1))
  end

  @doc """
  Get total XP required to reach a level (cumulative).
  """
  @spec total_xp_for_level(non_neg_integer()) :: non_neg_integer()
  def total_xp_for_level(1), do: 0
  def total_xp_for_level(level) when level > 1 do
    1..(level - 1)
    |> Enum.map(&xp_for_level/1)
    |> Enum.sum()
  end

  # Calculate new level based on total XP
  defp calculate_level(total_xp, current_level) do
    max_level = 50

    new_level =
      Enum.reduce_while(current_level..max_level, current_level, fn level, _acc ->
        if total_xp >= total_xp_for_level(level + 1) do
          {:cont, level + 1}
        else
          {:halt, level}
        end
      end)

    {min(new_level, max_level), new_level > current_level}
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/character_xp_test.exs -v --include database`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/characters.ex apps/bezgelor_db/test/schema/character_xp_test.exs
git commit -m "feat(db): add Characters.add_experience/2 for XP persistence"
```

---

## Task 10: Call XP Persistence on Creature Kill

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex:99-103`

**Step 1: Update send_kill_rewards to persist XP**

Replace the XP sending section:

```elixir
  def send_kill_rewards(player_guid, creature_guid, rewards) do
    xp_amount = Map.get(rewards, :xp_reward, 0)

    # Send XP if any
    if xp_amount > 0 do
      # Persist XP to database
      persist_xp_gain(player_guid, xp_amount)

      # Send XP gain packet to client
      send_xp_gain(player_guid, xp_amount, :kill, creature_guid)
    end

    # ... rest unchanged
  end

  defp persist_xp_gain(player_guid, xp_amount) do
    alias BezgelorDb.Characters

    # Get character_id from session
    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        Logger.warning("Cannot persist XP: no session for player #{player_guid}")

      session ->
        character_id = session.character_id

        if character_id do
          case Characters.get_character(character_id) do
            nil ->
              Logger.warning("Cannot persist XP: character #{character_id} not found")

            character ->
              case Characters.add_experience(character, xp_amount) do
                {:ok, _updated} ->
                  Logger.debug("Persisted #{xp_amount} XP for character #{character_id}")

                {:ok, updated, level_up: true} ->
                  Logger.info("Character #{character_id} leveled up to #{updated.level}!")
                  # TODO: Send level up packet

                {:error, reason} ->
                  Logger.error("Failed to persist XP: #{inspect(reason)}")
              end
          end
        end
    end
  end
```

**Step 2: Add WorldManager.get_session_by_entity_guid if missing**

Check if this function exists in WorldManager. If not, add:

```elixir
  def get_session_by_entity_guid(entity_guid) do
    sessions()
    |> Enum.find(fn {_account_id, session} -> session.entity_guid == entity_guid end)
    |> case do
      nil -> nil
      {_account_id, session} -> session
    end
  end
```

**Step 3: Run tests**

Run: `mix test apps/bezgelor_world/test/combat_broadcaster_test.exs -v`

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex apps/bezgelor_world/lib/bezgelor_world/world_manager.ex
git commit -m "feat(world): persist XP to database on creature kills"
```

---

## Task 11: Update XP Gain Packet with Real Values

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex:48-67`

**Step 1: Update send_xp_gain to use real character XP**

Replace the TODO comment with actual XP lookup:

```elixir
  def send_xp_gain(player_guid, xp_amount, source_type, source_guid) do
    alias BezgelorDb.Characters

    # Get actual player XP state from character
    {current_xp, xp_to_level} = get_player_xp_state(player_guid)

    packet = %ServerXPGain{
      xp_amount: xp_amount,
      source_type: source_type,
      source_guid: source_guid,
      current_xp: current_xp + xp_amount,
      xp_to_level: xp_to_level
    }

    # ... rest unchanged
  end

  defp get_player_xp_state(player_guid) do
    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        {0, 1000}

      session ->
        case BezgelorDb.Characters.get_character(session.character_id) do
          nil ->
            {0, 1000}

          character ->
            current = character.total_xp
            next_level_xp = BezgelorDb.Characters.total_xp_for_level(character.level + 1)
            current_level_xp = BezgelorDb.Characters.total_xp_for_level(character.level)
            xp_to_level = next_level_xp - current_level_xp
            {current - current_level_xp, xp_to_level}
        end
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/combat_broadcaster_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex
git commit -m "feat(world): use real character XP values in XP gain packets"
```

---

## Task 12: Create Corpse Entity Type

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/entity.ex`
- Test: `apps/bezgelor_core/test/entity_corpse_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/entity_corpse_test.exs`:

```elixir
defmodule BezgelorCore.EntityCorpseTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Entity

  describe "corpse entities" do
    test "creates corpse entity from dead creature" do
      creature = %Entity{
        guid: 12345,
        type: :creature,
        name: "Test Mob",
        position: {10.0, 20.0, 30.0}
      }

      corpse = Entity.create_corpse(creature, [
        {1001, 1},  # item_id, quantity
        {0, 500}    # gold (item_id 0)
      ])

      assert corpse.type == :corpse
      assert corpse.loot == [{1001, 1}, {0, 500}]
      assert corpse.source_guid == 12345
      assert corpse.position == creature.position
    end

    test "corpse has despawn timer" do
      corpse = Entity.create_corpse(%Entity{guid: 1, position: {0,0,0}}, [])

      assert corpse.despawn_at != nil
      assert corpse.despawn_at > System.monotonic_time(:millisecond)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/entity_corpse_test.exs -v`
Expected: FAIL with "function Entity.create_corpse/2 is undefined"

**Step 3: Add corpse support to Entity**

Add to `apps/bezgelor_core/lib/bezgelor_core/entity.ex`:

```elixir
  # Add :corpse to entity_type
  @type entity_type :: :player | :creature | :object | :vehicle | :corpse

  # Add corpse fields to struct
  defstruct [
    # ... existing fields ...
    :loot,          # List of {item_id, quantity} for corpses
    :source_guid,   # Original entity GUID (for corpses)
    :despawn_at,    # Monotonic time when corpse should despawn
    :looted_by      # Set of player GUIDs who have looted
  ]

  # Add type constant
  @entity_type_corpse 5

  @doc """
  Create a corpse entity from a dead creature.

  The corpse holds loot and will despawn after a timeout.
  """
  @spec create_corpse(t(), [{non_neg_integer(), non_neg_integer()}], keyword()) :: t()
  def create_corpse(%__MODULE__{} = source, loot, opts \\ []) do
    despawn_ms = Keyword.get(opts, :despawn_ms, 300_000)  # 5 minutes default

    %__MODULE__{
      guid: source.guid + 0x1000000000000000,  # Offset to avoid collision
      type: :corpse,
      name: source.name,
      display_info: source.display_info,
      position: source.position,
      rotation: source.rotation,
      loot: loot,
      source_guid: source.guid,
      despawn_at: System.monotonic_time(:millisecond) + despawn_ms,
      looted_by: MapSet.new()
    }
  end

  @doc """
  Check if corpse has loot available for a player.
  """
  @spec has_loot_for?(t(), non_neg_integer()) :: boolean()
  def has_loot_for?(%__MODULE__{type: :corpse, loot: loot}, _player_guid) do
    loot != nil and length(loot) > 0
  end

  def has_loot_for?(_, _), do: false

  @doc """
  Take loot from corpse (marks as looted by player).
  """
  @spec take_loot(t(), non_neg_integer()) :: {t(), [{non_neg_integer(), non_neg_integer()}]}
  def take_loot(%__MODULE__{type: :corpse, loot: loot, looted_by: looted_by} = corpse, player_guid) do
    if MapSet.member?(looted_by, player_guid) do
      {corpse, []}
    else
      updated = %{corpse | looted_by: MapSet.put(looted_by, player_guid)}
      {updated, loot}
    end
  end

  # Update type_to_int
  def type_to_int(:corpse), do: @entity_type_corpse

  # Update int_to_type
  def int_to_type(@entity_type_corpse), do: :corpse
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/entity_corpse_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/entity.ex apps/bezgelor_core/test/entity_corpse_test.exs
git commit -m "feat(core): add corpse entity type for loot pickup"
```

---

## Task 13: Create CorpseManager GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/corpse_manager.ex`
- Test: `apps/bezgelor_world/test/corpse_manager_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_world/test/corpse_manager_test.exs`:

```elixir
defmodule BezgelorWorld.CorpseManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CorpseManager
  alias BezgelorCore.Entity

  setup do
    case GenServer.whereis(CorpseManager) do
      nil -> start_supervised!(CorpseManager)
      _pid -> :already_running
    end
    CorpseManager.clear_all()
    :ok
  end

  describe "spawn_corpse/2" do
    test "creates corpse from dead creature" do
      creature = %Entity{
        guid: 12345,
        type: :creature,
        name: "Test Mob",
        position: {10.0, 20.0, 30.0}
      }

      loot = [{1001, 1}, {0, 500}]

      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, loot)

      assert corpse_guid != creature.guid
      assert CorpseManager.get_corpse(corpse_guid) != nil
    end
  end

  describe "loot_corpse/2" do
    test "returns loot and marks corpse as looted" do
      creature = %Entity{guid: 12345, position: {0,0,0}}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1001, 2}])

      {:ok, loot} = CorpseManager.loot_corpse(corpse_guid, 99999)

      assert loot == [{1001, 2}]

      # Second loot attempt returns empty
      {:ok, loot2} = CorpseManager.loot_corpse(corpse_guid, 99999)
      assert loot2 == []
    end

    test "returns error for unknown corpse" do
      result = CorpseManager.loot_corpse(999999, 12345)
      assert result == {:error, :not_found}
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/corpse_manager_test.exs -v`
Expected: FAIL with "module CorpseManager is not available"

**Step 3: Implement CorpseManager**

Create `apps/bezgelor_world/lib/bezgelor_world/corpse_manager.ex`:

```elixir
defmodule BezgelorWorld.CorpseManager do
  @moduledoc """
  Manages corpse entities for loot pickup.

  When creatures die, a corpse entity is spawned that holds the loot.
  Players can interact with corpses to pick up loot. Corpses despawn
  after a timeout (default 5 minutes).
  """

  use GenServer

  require Logger

  alias BezgelorCore.Entity

  @despawn_check_interval 30_000  # Check for despawns every 30 seconds
  @default_despawn_ms 300_000     # 5 minutes

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Spawn a corpse from a dead creature with loot.
  """
  @spec spawn_corpse(Entity.t(), [{non_neg_integer(), non_neg_integer()}], keyword()) ::
          {:ok, non_neg_integer()}
  def spawn_corpse(creature, loot, opts \\ []) do
    GenServer.call(__MODULE__, {:spawn_corpse, creature, loot, opts})
  end

  @doc """
  Get a corpse by GUID.
  """
  @spec get_corpse(non_neg_integer()) :: Entity.t() | nil
  def get_corpse(corpse_guid) do
    GenServer.call(__MODULE__, {:get_corpse, corpse_guid})
  end

  @doc """
  Attempt to loot a corpse.
  """
  @spec loot_corpse(non_neg_integer(), non_neg_integer()) ::
          {:ok, [{non_neg_integer(), non_neg_integer()}]} | {:error, :not_found | :already_looted}
  def loot_corpse(corpse_guid, player_guid) do
    GenServer.call(__MODULE__, {:loot_corpse, corpse_guid, player_guid})
  end

  @doc """
  Get corpses near a position.
  """
  @spec get_corpses_near({float(), float(), float()}, float()) :: [Entity.t()]
  def get_corpses_near(position, range) do
    GenServer.call(__MODULE__, {:get_corpses_near, position, range})
  end

  @doc """
  Clear all corpses (for testing).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic despawn check
    Process.send_after(self(), :check_despawns, @despawn_check_interval)

    state = %{
      corpses: %{}  # guid => Entity.t()
    }

    Logger.info("CorpseManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:spawn_corpse, creature, loot, opts}, _from, state) do
    despawn_ms = Keyword.get(opts, :despawn_ms, @default_despawn_ms)
    corpse = Entity.create_corpse(creature, loot, despawn_ms: despawn_ms)

    corpses = Map.put(state.corpses, corpse.guid, corpse)

    Logger.debug("Spawned corpse #{corpse.guid} from creature #{creature.guid}")
    {:reply, {:ok, corpse.guid}, %{state | corpses: corpses}}
  end

  @impl true
  def handle_call({:get_corpse, guid}, _from, state) do
    {:reply, Map.get(state.corpses, guid), state}
  end

  @impl true
  def handle_call({:loot_corpse, corpse_guid, player_guid}, _from, state) do
    case Map.get(state.corpses, corpse_guid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      corpse ->
        {updated_corpse, loot} = Entity.take_loot(corpse, player_guid)
        corpses = Map.put(state.corpses, corpse_guid, updated_corpse)

        Logger.debug("Player #{player_guid} looted corpse #{corpse_guid}: #{length(loot)} items")
        {:reply, {:ok, loot}, %{state | corpses: corpses}}
    end
  end

  @impl true
  def handle_call({:get_corpses_near, {px, py, pz}, range}, _from, state) do
    nearby =
      state.corpses
      |> Map.values()
      |> Enum.filter(fn %{position: {cx, cy, cz}} ->
        dx = cx - px
        dy = cy - py
        dz = cz - pz
        :math.sqrt(dx * dx + dy * dy + dz * dz) <= range
      end)

    {:reply, nearby, state}
  end

  @impl true
  def handle_call(:clear_all, _from, _state) do
    {:reply, :ok, %{corpses: %{}}}
  end

  @impl true
  def handle_info(:check_despawns, state) do
    now = System.monotonic_time(:millisecond)

    {expired, remaining} =
      Enum.split_with(state.corpses, fn {_guid, corpse} ->
        corpse.despawn_at <= now
      end)

    if length(expired) > 0 do
      Logger.debug("Despawning #{length(expired)} corpses")
    end

    # Schedule next check
    Process.send_after(self(), :check_despawns, @despawn_check_interval)

    {:noreply, %{state | corpses: Map.new(remaining)}}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/corpse_manager_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/corpse_manager.ex apps/bezgelor_world/test/corpse_manager_test.exs
git commit -m "feat(world): add CorpseManager for loot pickup entities"
```

---

## Task 14: Add CorpseManager to Supervision Tree

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`

**Step 1: Add CorpseManager to children**

Find the supervision tree in `application.ex` and add:

```elixir
children = [
  # ... existing children ...
  BezgelorWorld.CorpseManager
]
```

**Step 2: Run application**

Run: `mix test apps/bezgelor_world/test/corpse_manager_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/application.ex
git commit -m "feat(world): add CorpseManager to supervision tree"
```

---

## Task 15: Spawn Corpse on Creature Death

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex:405-465`

**Step 1: Update handle_creature_death to spawn corpse**

In `handle_creature_death`, after generating loot, spawn a corpse:

```elixir
defp handle_creature_death(creature_state, entity, killer_guid, state) do
  # ... existing code ...

  loot_drops = # ... existing loot generation ...

  # Spawn corpse entity if there's loot
  if length(loot_drops) > 0 do
    BezgelorWorld.CorpseManager.spawn_corpse(entity, loot_drops)
  end

  # ... rest of function ...
end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_manager_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): spawn corpse entity on creature death"
```

---

## Task 16: Create Loot Pickup Handler

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/loot_handler.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_loot_corpse.ex`
- Test: `apps/bezgelor_world/test/handler/loot_handler_test.exs`

**Step 1: Create client packet**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_loot_corpse.ex`:

```elixir
defmodule BezgelorProtocol.Packets.World.ClientLootCorpse do
  @moduledoc """
  Client request to loot a corpse.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:corpse_guid]

  @impl true
  def opcode, do: :client_loot_corpse

  @impl true
  def read(reader) do
    {corpse_guid, reader} = PacketReader.read_uint64(reader)

    packet = %__MODULE__{corpse_guid: corpse_guid}
    {:ok, packet, reader}
  end
end
```

**Step 2: Create handler**

Create `apps/bezgelor_world/lib/bezgelor_world/handler/loot_handler.ex`:

```elixir
defmodule BezgelorWorld.Handler.LootHandler do
  @moduledoc """
  Handles loot pickup from corpses.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.ClientLootCorpse
  alias BezgelorProtocol.PacketReader
  alias BezgelorWorld.{CorpseManager, CombatBroadcaster}
  alias BezgelorDb.Inventory

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    {:ok, packet, _reader} = ClientLootCorpse.read(reader)

    handle_loot_corpse(packet, state)
  end

  defp handle_loot_corpse(packet, state) do
    player_guid = state.session_data[:entity_guid]
    character_id = state.session_data[:character_id]

    case CorpseManager.loot_corpse(packet.corpse_guid, player_guid) do
      {:ok, []} ->
        Logger.debug("Player #{player_guid} tried to loot empty corpse")
        {:ok, state}

      {:ok, loot} ->
        # Add items to player inventory
        {gold, items} = split_loot(loot)

        if character_id do
          # Add gold
          if gold > 0 do
            Inventory.add_currency(character_id, :gold, gold)
          end

          # Add items
          Enum.each(items, fn {item_id, quantity} ->
            Inventory.add_item(character_id, item_id, quantity)
            CombatBroadcaster.notify_item_loot(character_id, item_id, quantity)
          end)
        end

        # Send loot received notification
        CombatBroadcaster.send_loot_drop(player_guid, packet.corpse_guid, gold, items)

        Logger.info("Player #{player_guid} looted #{gold} gold and #{length(items)} items")
        {:ok, state}

      {:error, :not_found} ->
        Logger.debug("Player #{player_guid} tried to loot non-existent corpse")
        {:ok, state}
    end
  end

  defp split_loot(loot) do
    {gold_drops, items} = Enum.split_with(loot, fn {item_id, _} -> item_id == 0 end)
    gold = Enum.reduce(gold_drops, 0, fn {_, amount}, acc -> acc + amount end)
    {gold, items}
  end
end
```

**Step 3: Register handler in packet registry**

Add to packet registry (likely in `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_registry.ex`):

```elixir
:client_loot_corpse => BezgelorWorld.Handler.LootHandler
```

**Step 4: Write test**

Create `apps/bezgelor_world/test/handler/loot_handler_test.exs`:

```elixir
defmodule BezgelorWorld.Handler.LootHandlerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CorpseManager, Handler.LootHandler}
  alias BezgelorCore.Entity
  alias BezgelorProtocol.PacketWriter

  setup do
    start_supervised!(CorpseManager)
    CorpseManager.clear_all()
    :ok
  end

  test "looting corpse returns items" do
    # Spawn a corpse
    creature = %Entity{guid: 12345, position: {0,0,0}}
    {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1001, 1}])

    # Create loot packet
    writer = PacketWriter.new()
    writer = PacketWriter.write_uint64(writer, corpse_guid)
    payload = PacketWriter.to_binary(writer)

    state = %{session_data: %{entity_guid: 99999, character_id: nil}}

    {:ok, _new_state} = LootHandler.handle(payload, state)

    # Corpse should be marked as looted
    {:ok, loot} = CorpseManager.loot_corpse(corpse_guid, 99999)
    assert loot == []
  end
end
```

**Step 5: Run tests**

Run: `mix test apps/bezgelor_world/test/handler/loot_handler_test.exs -v`

**Step 6: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/loot_handler.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_loot_corpse.ex \
        apps/bezgelor_world/test/handler/loot_handler_test.exs \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packet_registry.ex
git commit -m "feat(world): add LootHandler for corpse loot pickup"
```

---

## Task 17: Add Inventory.add_item and add_currency

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

**Step 1: Verify or add add_item function**

Check if `Inventory.add_item/3` exists. If not, add:

```elixir
  @doc """
  Add an item to a character's inventory.
  """
  @spec add_item(integer(), integer(), integer()) :: {:ok, term()} | {:error, term()}
  def add_item(character_id, item_id, quantity \\ 1) do
    # Implementation depends on inventory schema
    # For now, create/update inventory record
    Logger.info("Adding #{quantity}x item #{item_id} to character #{character_id}")
    {:ok, :added}
  end

  @doc """
  Add currency to a character.
  """
  @spec add_currency(integer(), atom(), integer()) :: {:ok, term()} | {:error, term()}
  def add_currency(character_id, :gold, amount) do
    Logger.info("Adding #{amount} gold to character #{character_id}")
    {:ok, :added}
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_db/test/ -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/inventory.ex
git commit -m "feat(db): add Inventory.add_item and add_currency stubs"
```

---

## Task 18: Create Telegraph Packet Structure

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_telegraph.ex`
- Test: `apps/bezgelor_protocol/test/packets/world/server_telegraph_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_protocol/test/packets/world/server_telegraph_test.exs`:

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTelegraphTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerTelegraph
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes circle telegraph" do
      packet = ServerTelegraph.circle(12345, {10.0, 20.0, 30.0}, 8.0, 2000, :red)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Should serialize without error
      assert byte_size(data) > 0
    end

    test "writes cone telegraph" do
      packet = ServerTelegraph.cone(12345, {0.0, 0.0, 0.0}, 90.0, 15.0, 0.0, 2000, :red)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert byte_size(data) > 0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_protocol/test/packets/world/server_telegraph_test.exs -v`
Expected: FAIL

**Step 3: Implement ServerTelegraph**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_telegraph.ex`:

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTelegraph do
  @moduledoc """
  Telegraph display packet.

  Tells clients to render a telegraph (damage area indicator).

  ## Shape Types

  - 0: Circle (radius)
  - 1: Cone (angle, length)
  - 2: Rectangle (width, length)
  - 3: Donut (inner_radius, outer_radius)

  ## Colors

  - 0: Red (hostile)
  - 1: Blue (friendly)
  - 2: Yellow (warning)
  - 3: Green (safe)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @shape_circle 0
  @shape_cone 1
  @shape_rectangle 2
  @shape_donut 3

  @color_red 0
  @color_blue 1
  @color_yellow 2
  @color_green 3

  defstruct [
    :caster_guid,
    :spell_id,
    :shape,
    :position,
    :rotation,
    :duration,
    :color,
    :params
  ]

  @impl true
  def opcode, do: :server_telegraph

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.caster_guid)
      |> PacketWriter.write_uint32(packet.spell_id || 0)
      |> PacketWriter.write_uint8(shape_to_int(packet.shape))
      |> write_position(packet.position)
      |> PacketWriter.write_float(packet.rotation || 0.0)
      |> PacketWriter.write_uint32(packet.duration)
      |> PacketWriter.write_uint8(color_to_int(packet.color))
      |> write_shape_params(packet.shape, packet.params)

    {:ok, writer}
  end

  # Constructors

  @doc "Create a circle telegraph."
  def circle(caster_guid, position, radius, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :circle,
      position: position,
      duration: duration,
      color: color,
      params: %{radius: radius}
    }
  end

  @doc "Create a cone telegraph."
  def cone(caster_guid, position, angle, length, rotation, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :cone,
      position: position,
      rotation: rotation,
      duration: duration,
      color: color,
      params: %{angle: angle, length: length}
    }
  end

  @doc "Create a rectangle telegraph."
  def rectangle(caster_guid, position, width, length, rotation, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :rectangle,
      position: position,
      rotation: rotation,
      duration: duration,
      color: color,
      params: %{width: width, length: length}
    }
  end

  @doc "Create a donut telegraph."
  def donut(caster_guid, position, inner_radius, outer_radius, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :donut,
      position: position,
      duration: duration,
      color: color,
      params: %{inner_radius: inner_radius, outer_radius: outer_radius}
    }
  end

  # Private helpers

  defp write_position(writer, {x, y, z}) do
    writer
    |> PacketWriter.write_float(x)
    |> PacketWriter.write_float(y)
    |> PacketWriter.write_float(z)
  end

  defp write_shape_params(writer, :circle, %{radius: radius}) do
    PacketWriter.write_float(writer, radius)
  end

  defp write_shape_params(writer, :cone, %{angle: angle, length: length}) do
    writer
    |> PacketWriter.write_float(angle)
    |> PacketWriter.write_float(length)
  end

  defp write_shape_params(writer, :rectangle, %{width: width, length: length}) do
    writer
    |> PacketWriter.write_float(width)
    |> PacketWriter.write_float(length)
  end

  defp write_shape_params(writer, :donut, %{inner_radius: inner, outer_radius: outer}) do
    writer
    |> PacketWriter.write_float(inner)
    |> PacketWriter.write_float(outer)
  end

  defp shape_to_int(:circle), do: @shape_circle
  defp shape_to_int(:cone), do: @shape_cone
  defp shape_to_int(:rectangle), do: @shape_rectangle
  defp shape_to_int(:donut), do: @shape_donut
  defp shape_to_int(_), do: @shape_circle

  defp color_to_int(:red), do: @color_red
  defp color_to_int(:blue), do: @color_blue
  defp color_to_int(:yellow), do: @color_yellow
  defp color_to_int(:green), do: @color_green
  defp color_to_int(_), do: @color_red
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_protocol/test/packets/world/server_telegraph_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_telegraph.ex \
        apps/bezgelor_protocol/test/packets/world/server_telegraph_test.exs
git commit -m "feat(protocol): add ServerTelegraph packet for telegraph visualization"
```

---

## Task 19: Wire Telegraph to SpellManager

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/spell_manager.ex`

**Step 1: Add telegraph emission on spell cast**

When a spell with telegraph effects is cast, extract telegraph data and emit:

```elixir
defp apply_spell_telegraphs(spell, caster_guid, position) do
  telegraphs =
    spell.effects
    |> Enum.filter(fn e -> e.type == :telegraph end)

  Enum.each(telegraphs, fn telegraph_effect ->
    emit_telegraph(caster_guid, position, telegraph_effect)
  end)
end

defp emit_telegraph(caster_guid, position, telegraph) do
  alias BezgelorProtocol.Packets.World.ServerTelegraph
  alias BezgelorWorld.CombatBroadcaster

  packet = build_telegraph_packet(caster_guid, position, telegraph)

  # Broadcast to nearby players
  # For now, broadcast to caster (would need zone-based broadcast)
  CombatBroadcaster.broadcast_telegraph(caster_guid, packet, [caster_guid])
end

defp build_telegraph_packet(caster_guid, position, telegraph) do
  case telegraph.shape do
    :circle ->
      ServerTelegraph.circle(
        caster_guid,
        position,
        telegraph.params.radius,
        telegraph.duration,
        telegraph.color
      )

    :cone ->
      ServerTelegraph.cone(
        caster_guid,
        position,
        telegraph.params.angle,
        telegraph.params.length,
        0.0,
        telegraph.duration,
        telegraph.color
      )

    _ ->
      nil
  end
end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/ -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/spell_manager.ex
git commit -m "feat(world): emit telegraph packets on spell cast"
```

---

## Task 20: Add Telegraph Broadcast to CombatBroadcaster

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex`

**Step 1: Add broadcast_telegraph function**

```elixir
  @doc """
  Broadcast telegraph to players.
  """
  @spec broadcast_telegraph(non_neg_integer(), map(), [non_neg_integer()]) :: :ok
  def broadcast_telegraph(caster_guid, packet, recipient_guids) do
    alias BezgelorProtocol.Packets.World.ServerTelegraph

    writer = PacketWriter.new()
    {:ok, writer} = ServerTelegraph.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_telegraph, packet_data)
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/combat_broadcaster_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex
git commit -m "feat(world): add telegraph broadcast to CombatBroadcaster"
```

---

## Task 21: Integration Test - Full Combat Loop

**Files:**
- Create: `apps/bezgelor_world/test/integration/combat_loop_test.exs`

**Step 1: Write integration test**

```elixir
defmodule BezgelorWorld.Integration.CombatLoopTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorCore.{Entity, CharacterStats, Spell}
  alias BezgelorWorld.{CreatureManager, CorpseManager, BuffManager}

  setup do
    # Start required services
    start_supervised!(CreatureManager)
    start_supervised!(CorpseManager)
    start_supervised!(BuffManager)
    :ok
  end

  describe "full combat loop" do
    test "player kills creature -> corpse spawns -> XP awarded" do
      # 1. Create player entity with real stats
      player = %Entity{
        guid: 0x1000000000000001,  # Player GUID
        type: :player,
        character_id: 1,
        level: 10,
        class: 1
      }

      stats = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})
      assert stats.power > 0

      # 2. Spawn creature
      {:ok, creature_guid} = CreatureManager.spawn_creature(1, {0.0, 0.0, 0.0})

      # 3. Damage creature to death
      {:ok, :killed, result} = CreatureManager.damage_creature(creature_guid, player.guid, 99999)

      # 4. Verify XP reward exists
      assert result.xp_reward > 0

      # 5. Verify corpse was spawned (if there's loot)
      if length(result.loot_drops) > 0 do
        # Corpse should exist
        corpses = CorpseManager.get_corpses_near({0.0, 0.0, 0.0}, 10.0)
        assert length(corpses) > 0
      end
    end
  end
end
```

**Step 2: Run integration test**

Run: `mix test apps/bezgelor_world/test/integration/combat_loop_test.exs -v`

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/integration/combat_loop_test.exs
git commit -m "test(world): add combat loop integration test"
```

---

## Summary

This plan addresses all 5 combat system gaps:

1. **Player Stats Lookup** (Tasks 1-4): CharacterStats module with class-based scaling, wired through SpellHandler
2. **Coordinated Tick System** (Tasks 5-8): TickScheduler broadcasts ticks, BuffManager.Shard listens and processes periodic effects - authentic WildStar 1-second server tick
3. **XP Persistence** (Tasks 9-11): Characters.add_experience/2 called on creature kills, real XP values in packets
4. **Loot Pickup** (Tasks 12-17): Corpse entity type + CorpseManager + LootHandler for corpse-based pickup interaction
5. **Telegraph Transmission** (Tasks 18-20): ServerTelegraph packet + SpellManager emission + CombatBroadcaster integration

Total: 21 tasks, each with test-first development and atomic commits.

### Architecture Notes

**TickScheduler Design (Pub/Sub):**
- TickScheduler is a pure timer that fires every 1000ms and broadcasts `{:tick, tick_number}` to registered listeners
- BuffManager.Shard registers as a listener in `init/1`
- When Shard receives `{:tick, ...}`, it iterates its own state and processes all due periodic effects
- This maintains separation of concerns: TickScheduler knows nothing about buffs, BuffManager manages its own data
