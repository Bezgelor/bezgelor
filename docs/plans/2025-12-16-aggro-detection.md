# Aggro Detection System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement WildStar-authentic creature aggro detection where aggressive creatures automatically detect and attack nearby players based on aggro radius, with threat-based targeting, leash mechanics, and social aggro for group pulls.

**Architecture:** Leverage existing `CreatureTemplate.aggro_range` (unused), `SpatialGrid.entities_in_range/3` for efficient queries, and the `AI` state machine. Aggro checks occur during idle-state AI ticks. Social aggro uses faction matching to pull nearby creatures. Leash distance uses existing `leash_range` field with evade state.

**Tech Stack:** Elixir/OTP, ETS for creature templates, SpatialGrid for spatial queries, GenServer tick processing.

---

## Implementation Order

1. **Tasks 1-4: Core Aggro Detection** - Idle creatures detect players in aggro range
2. **Tasks 5-7: Faction-Based Filtering** - Only aggro on enemy factions
3. **Tasks 8-10: Social Aggro** - Nearby same-faction creatures join combat
4. **Tasks 11-13: Leash Distance** - Creatures evade when pulled too far
5. **Tasks 14-16: Combat Timeout Cleanup** - Exit combat when target unreachable/dead
6. **Task 17: Integration Test** - Full aggro flow validation

---

## Task 1: Add Aggro Detection to AI Idle Tick

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_aggro_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/ai_aggro_test.exs`:

```elixir
defmodule BezgelorCore.AIAggroTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "check_aggro/3" do
    test "returns target when player in aggro range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}  # 5 units away
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == {:aggro, 12345}
    end

    test "returns nil when no players in range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {50.0, 0.0, 0.0}}  # 50 units away
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns nil when already in combat" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(99999)

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns closest player when multiple in range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {8.0, 0.0, 0.0}},  # 8 units
        %{guid: 22222, position: {3.0, 0.0, 0.0}},  # 3 units (closest)
        %{guid: 33333, position: {6.0, 0.0, 0.0}}   # 6 units
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == {:aggro, 22222}
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: FAIL with "function AI.check_aggro/3 is undefined"

**Step 3: Implement check_aggro/3**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex` after the `in_combat?/1` function:

```elixir
  @doc """
  Check for players in aggro range.

  Only checks when creature is idle (not in combat, evading, or dead).
  Returns the closest player if any are within aggro range.

  ## Parameters

  - `ai` - The AI state
  - `nearby_players` - List of %{guid: integer, position: {x, y, z}} maps
  - `aggro_range` - Aggro detection radius

  ## Returns

  - `{:aggro, player_guid}` if a player is detected
  - `nil` if no players in range or AI is busy
  """
  @spec check_aggro(t(), [map()], float()) :: {:aggro, non_neg_integer()} | nil
  def check_aggro(%__MODULE__{state: state}, _nearby_players, _aggro_range)
      when state in [:combat, :evade, :dead] do
    nil
  end

  def check_aggro(%__MODULE__{spawn_position: spawn_pos}, nearby_players, aggro_range) do
    nearby_players
    |> Enum.map(fn player ->
      dist = distance(spawn_pos, player.position)
      {dist, player.guid}
    end)
    |> Enum.filter(fn {dist, _guid} -> dist <= aggro_range end)
    |> Enum.min_by(fn {dist, _guid} -> dist end, fn -> nil end)
    |> case do
      nil -> nil
      {_dist, guid} -> {:aggro, guid}
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: PASS (4 tests, 0 failures)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_aggro_test.exs
git commit -m "feat(core): add AI.check_aggro/3 for aggro range detection"
```

---

## Task 2: Wire Aggro Check to CreatureManager AI Tick

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`
- Test: `apps/bezgelor_world/test/creature_aggro_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_world/test/creature_aggro_test.exs`:

```elixir
defmodule BezgelorWorld.CreatureAggroTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager
  alias BezgelorCore.{AI, Entity}

  setup do
    # Start CreatureManager if not running
    case GenServer.whereis(CreatureManager) do
      nil -> start_supervised!(CreatureManager)
      _pid -> :ok
    end

    # Clear any existing creatures
    CreatureManager.clear_all()
    :ok
  end

  describe "aggro detection" do
    test "creature enters combat when player enters aggro range" do
      # Spawn an aggressive creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(
        2,  # Forest Wolf template (aggressive, aggro_range: 15.0)
        {0.0, 0.0, 0.0}
      )

      # Simulate player entity nearby
      player = %{
        guid: 0x1000000000000001,
        position: {10.0, 0.0, 0.0},  # Within 15.0 aggro range
        type: :player
      }

      # Trigger aggro check with player context
      CreatureManager.check_aggro_for_creature(creature_guid, [player])

      # Verify creature entered combat
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.state == :combat
      assert state.ai.target_guid == player.guid
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/creature_aggro_test.exs -v`
Expected: FAIL with "function CreatureManager.check_aggro_for_creature/2 is undefined"

**Step 3: Add check_aggro_for_creature/2 and get_creature_state/1**

Add to `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex` in the Client API section:

```elixir
  @doc """
  Check aggro for a specific creature against nearby players.
  """
  @spec check_aggro_for_creature(non_neg_integer(), [map()]) :: :ok
  def check_aggro_for_creature(creature_guid, nearby_players) do
    GenServer.cast(__MODULE__, {:check_aggro, creature_guid, nearby_players})
  end

  @doc """
  Get the current state of a creature (for testing).
  """
  @spec get_creature_state(non_neg_integer()) :: {:ok, creature_state()} | :error
  def get_creature_state(creature_guid) do
    GenServer.call(__MODULE__, {:get_creature_state, creature_guid})
  end
```

Add the handle_cast and handle_call clauses:

```elixir
  @impl true
  def handle_cast({:check_aggro, creature_guid, nearby_players}, state) do
    case Map.get(state.creatures, creature_guid) do
      nil ->
        {:noreply, state}

      creature_state ->
        case check_and_enter_combat(creature_state, nearby_players) do
          {:entered_combat, new_creature_state} ->
            creatures = Map.put(state.creatures, creature_guid, new_creature_state)
            {:noreply, %{state | creatures: creatures}}

          :no_aggro ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call({:get_creature_state, creature_guid}, _from, state) do
    case Map.get(state.creatures, creature_guid) do
      nil -> {:reply, :error, state}
      creature_state -> {:reply, {:ok, creature_state}, state}
    end
  end

  # Check aggro and enter combat if player detected
  defp check_and_enter_combat(creature_state, nearby_players) do
    template = creature_state.template
    aggro_range = template.aggro_range || 0.0

    # Only aggressive creatures auto-aggro
    if template.ai_type == :aggressive and aggro_range > 0 do
      case AI.check_aggro(creature_state.ai, nearby_players, aggro_range) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(creature_state.ai, player_guid)
          Logger.info("Creature #{creature_state.entity.name} aggro'd on player #{player_guid}")
          {:entered_combat, %{creature_state | ai: new_ai}}

        nil ->
          :no_aggro
      end
    else
      :no_aggro
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/creature_aggro_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex apps/bezgelor_world/test/creature_aggro_test.exs
git commit -m "feat(world): add check_aggro_for_creature to CreatureManager"
```

---

## Task 3: Integrate Aggro Check into AI Tick Loop

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Find the AI tick processing function**

The `process_creature_ai/2` function handles individual creature AI ticks. We need to add aggro checking for idle creatures.

**Step 2: Add aggro checking to process_creature_ai/2**

Find the function and add aggro detection for idle state. Locate:

```elixir
defp process_creature_ai(creature_state, state) do
```

Add a new clause at the beginning for idle aggro checking:

```elixir
  defp process_creature_ai(%{ai: %{state: :idle}} = creature_state, state) do
    # Check for nearby players to aggro
    template = creature_state.template

    if template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0 do
      nearby_players = get_nearby_players_for_aggro(creature_state, state)

      case AI.check_aggro(creature_state.ai, nearby_players, template.aggro_range) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(creature_state.ai, player_guid)
          Logger.debug("Creature #{creature_state.entity.name} aggro'd player #{player_guid}")
          {:updated, %{creature_state | ai: new_ai}}

        nil ->
          # No aggro, continue with normal idle behavior (wandering, etc)
          process_idle_behavior(creature_state, state)
      end
    else
      process_idle_behavior(creature_state, state)
    end
  end

  # Helper to get nearby player entities for aggro checking
  defp get_nearby_players_for_aggro(creature_state, _state) do
    zone_key = {creature_state.world_id, 1}  # Assuming instance 1
    creature_pos = creature_state.entity.position
    aggro_range = creature_state.template.aggro_range || 15.0

    case ZoneInstance.entities_in_range(zone_key, creature_pos, aggro_range) do
      {:ok, entities} ->
        entities
        |> Enum.filter(fn e -> e.type == :player end)
        |> Enum.map(fn e -> %{guid: e.guid, position: e.position} end)

      _ ->
        []
    end
  end

  # Extract existing idle behavior (wandering) to separate function
  defp process_idle_behavior(creature_state, state) do
    # Existing idle tick logic (wandering, etc) goes here
    # ... copy existing :idle handling code ...
    :unchanged
  end
```

**Step 3: Run existing tests**

Run: `mix test apps/bezgelor_world/test/creature_manager_test.exs -v`
Expected: PASS

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): integrate aggro check into AI tick loop for idle creatures"
```

---

## Task 4: Add Aggro Detection Test with Zone Instance

**Files:**
- Test: `apps/bezgelor_world/test/creature_aggro_zone_test.exs`

**Step 1: Write integration test with zone instance**

Create `apps/bezgelor_world/test/creature_aggro_zone_test.exs`:

```elixir
defmodule BezgelorWorld.CreatureAggroZoneTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CreatureManager, ZoneInstance}
  alias BezgelorCore.Entity

  @moduletag :integration

  setup do
    start_supervised!(CreatureManager)
    CreatureManager.clear_all()

    # Start a test zone instance
    zone_key = {1, 1}
    start_supervised!({ZoneInstance, zone_id: 1, instance_id: 1})

    %{zone_key: zone_key}
  end

  describe "aggro detection with zone instance" do
    test "creature detects player in same zone", %{zone_key: zone_key} do
      # Add player entity to zone at position (10, 0, 0)
      player_entity = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        name: "TestPlayer",
        position: {10.0, 0.0, 0.0},
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity(zone_key, player_entity)

      # Spawn aggressive creature at origin (within 15.0 aggro range of player)
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Trigger an AI tick
      send(CreatureManager, {:tick, 1})
      Process.sleep(50)  # Allow async processing

      # Verify creature entered combat
      {:ok, creature_state} = CreatureManager.get_creature_state(creature_guid)
      assert creature_state.ai.state == :combat
      assert creature_state.ai.target_guid == player_entity.guid
    end

    test "creature ignores player outside aggro range", %{zone_key: zone_key} do
      # Add player entity far away (50 units)
      player_entity = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        name: "TestPlayer",
        position: {50.0, 0.0, 0.0},
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity(zone_key, player_entity)

      # Spawn creature (aggro range 15.0)
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Trigger AI tick
      send(CreatureManager, {:tick, 1})
      Process.sleep(50)

      # Verify creature stays idle
      {:ok, creature_state} = CreatureManager.get_creature_state(creature_guid)
      assert creature_state.ai.state == :idle
    end
  end
end
```

**Step 2: Run integration test**

Run: `mix test apps/bezgelor_world/test/creature_aggro_zone_test.exs -v`
Expected: PASS (may need adjustments based on actual zone instance API)

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/creature_aggro_zone_test.exs
git commit -m "test(world): add creature aggro zone integration tests"
```

---

## Task 5: Add Faction System for Aggro Filtering

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/faction.ex`
- Test: `apps/bezgelor_core/test/faction_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/faction_test.exs`:

```elixir
defmodule BezgelorCore.FactionTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Faction

  describe "hostile?/2" do
    test "exile and dominion are hostile" do
      assert Faction.hostile?(:exile, :dominion)
      assert Faction.hostile?(:dominion, :exile)
    end

    test "same faction is not hostile" do
      refute Faction.hostile?(:exile, :exile)
      refute Faction.hostile?(:dominion, :dominion)
    end

    test "hostile creatures are hostile to players" do
      assert Faction.hostile?(:hostile, :exile)
      assert Faction.hostile?(:hostile, :dominion)
    end

    test "neutral creatures are not hostile" do
      refute Faction.hostile?(:neutral, :exile)
      refute Faction.hostile?(:neutral, :dominion)
    end

    test "friendly creatures are not hostile" do
      refute Faction.hostile?(:friendly, :exile)
      refute Faction.hostile?(:friendly, :dominion)
    end
  end

  describe "faction_from_id/1" do
    test "maps known faction IDs" do
      assert Faction.faction_from_id(166) == :exile
      assert Faction.faction_from_id(167) == :dominion
      assert Faction.faction_from_id(0) == :neutral
    end

    test "unknown IDs default to neutral" do
      assert Faction.faction_from_id(99999) == :neutral
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/faction_test.exs -v`
Expected: FAIL with "module Faction is not available"

**Step 3: Implement Faction module**

Create `apps/bezgelor_core/lib/bezgelor_core/faction.ex`:

```elixir
defmodule BezgelorCore.Faction do
  @moduledoc """
  Faction relationship system for WildStar.

  WildStar has two main player factions (Exile and Dominion) plus
  creature factions that determine hostility.

  ## Faction Types

  - `:exile` - Exile player faction
  - `:dominion` - Dominion player faction
  - `:hostile` - Hostile to all players
  - `:neutral` - Neutral to all (won't aggro)
  - `:friendly` - Friendly to all players
  """

  @type faction :: :exile | :dominion | :hostile | :neutral | :friendly

  # Known faction IDs from WildStar data
  @exile_faction_id 166
  @dominion_faction_id 167

  # Hostile creature factions (IDs that are hostile to players)
  @hostile_faction_ids [281, 282, 283, 284, 285]

  @doc """
  Check if two factions are hostile to each other.
  """
  @spec hostile?(faction(), faction()) :: boolean()
  def hostile?(:hostile, _target), do: true
  def hostile?(_source, :hostile), do: true
  def hostile?(:neutral, _target), do: false
  def hostile?(_source, :neutral), do: false
  def hostile?(:friendly, _target), do: false
  def hostile?(_source, :friendly), do: false
  def hostile?(:exile, :dominion), do: true
  def hostile?(:dominion, :exile), do: true
  def hostile?(same, same), do: false
  def hostile?(_, _), do: false

  @doc """
  Convert a faction ID to faction atom.
  """
  @spec faction_from_id(non_neg_integer()) :: faction()
  def faction_from_id(@exile_faction_id), do: :exile
  def faction_from_id(@dominion_faction_id), do: :dominion
  def faction_from_id(id) when id in @hostile_faction_ids, do: :hostile
  def faction_from_id(0), do: :neutral
  def faction_from_id(_), do: :neutral

  @doc """
  Check if a creature faction ID is hostile to a player faction.
  """
  @spec creature_hostile_to_player?(non_neg_integer(), faction()) :: boolean()
  def creature_hostile_to_player?(creature_faction_id, player_faction) do
    creature_faction = faction_from_id(creature_faction_id)
    hostile?(creature_faction, player_faction)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/faction_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/faction.ex apps/bezgelor_core/test/faction_test.exs
git commit -m "feat(core): add Faction module for hostility checks"
```

---

## Task 6: Filter Aggro by Faction

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_aggro_test.exs`

**Step 1: Add test for faction filtering**

Add to `apps/bezgelor_core/test/ai_aggro_test.exs`:

```elixir
  describe "check_aggro_with_faction/4" do
    test "only aggros hostile faction players" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {5.0, 0.0, 0.0}, faction: :exile},
        %{guid: 22222, position: {5.0, 0.0, 0.0}, faction: :dominion}
      ]

      # Creature is hostile faction - aggros both
      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :hostile)
      assert result == {:aggro, 11111} or result == {:aggro, 22222}
    end

    test "friendly creatures don't aggro" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}, faction: :exile}
      ]

      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :friendly)
      assert result == nil
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: FAIL

**Step 3: Implement check_aggro_with_faction/4**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex`:

```elixir
  @doc """
  Check for players in aggro range, filtering by faction hostility.

  Only returns players that are hostile to the creature's faction.
  """
  @spec check_aggro_with_faction(t(), [map()], float(), Faction.faction()) ::
          {:aggro, non_neg_integer()} | nil
  def check_aggro_with_faction(%__MODULE__{state: state}, _nearby_players, _aggro_range, _faction)
      when state in [:combat, :evade, :dead] do
    nil
  end

  def check_aggro_with_faction(%__MODULE__{spawn_position: spawn_pos}, nearby_players, aggro_range, creature_faction) do
    alias BezgelorCore.Faction

    nearby_players
    |> Enum.filter(fn player ->
      player_faction = Map.get(player, :faction, :exile)
      Faction.hostile?(creature_faction, player_faction)
    end)
    |> Enum.map(fn player ->
      dist = distance(spawn_pos, player.position)
      {dist, player.guid}
    end)
    |> Enum.filter(fn {dist, _guid} -> dist <= aggro_range end)
    |> Enum.min_by(fn {dist, _guid} -> dist end, fn -> nil end)
    |> case do
      nil -> nil
      {_dist, guid} -> {:aggro, guid}
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_aggro_test.exs
git commit -m "feat(core): add faction-based aggro filtering to AI"
```

---

## Task 7: Update CreatureManager to Use Faction Filtering

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Update get_nearby_players_for_aggro to include faction**

Modify the helper function:

```elixir
  defp get_nearby_players_for_aggro(creature_state, _state) do
    zone_key = {creature_state.world_id, 1}
    creature_pos = creature_state.entity.position
    aggro_range = creature_state.template.aggro_range || 15.0

    case ZoneInstance.entities_in_range(zone_key, creature_pos, aggro_range) do
      {:ok, entities} ->
        entities
        |> Enum.filter(fn e -> e.type == :player end)
        |> Enum.map(fn e ->
          %{
            guid: e.guid,
            position: e.position,
            faction: Map.get(e, :faction, :exile)  # Include faction
          }
        end)

      _ ->
        []
    end
  end
```

**Step 2: Update aggro check to use faction**

In the `process_creature_ai` for idle state, update to use faction:

```elixir
  defp process_creature_ai(%{ai: %{state: :idle}} = creature_state, state) do
    template = creature_state.template

    if template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0 do
      nearby_players = get_nearby_players_for_aggro(creature_state, state)
      creature_faction = Faction.faction_from_id(template.faction_id || 0)

      case AI.check_aggro_with_faction(creature_state.ai, nearby_players, template.aggro_range, creature_faction) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(creature_state.ai, player_guid)
          Logger.debug("Creature #{creature_state.entity.name} aggro'd player #{player_guid}")
          {:updated, %{creature_state | ai: new_ai}}

        nil ->
          process_idle_behavior(creature_state, state)
      end
    else
      process_idle_behavior(creature_state, state)
    end
  end
```

**Step 3: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_aggro_test.exs -v`
Expected: PASS

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): use faction-based aggro filtering in CreatureManager"
```

---

## Task 8: Add Social Aggro to AI

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_aggro_test.exs`

**Step 1: Add test for social aggro signal**

Add to `apps/bezgelor_core/test/ai_aggro_test.exs`:

```elixir
  describe "social_aggro/2" do
    test "idle creature can receive social aggro" do
      ai = AI.new({0.0, 0.0, 0.0})

      new_ai = AI.social_aggro(ai, 12345)

      assert new_ai.state == :combat
      assert new_ai.target_guid == 12345
    end

    test "creature already in combat ignores social aggro" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(11111)

      new_ai = AI.social_aggro(ai, 22222)

      assert new_ai.target_guid == 11111  # Keeps original target
    end

    test "evading creature ignores social aggro" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.start_evade()

      new_ai = AI.social_aggro(ai, 12345)

      assert new_ai.state == :evade
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: FAIL

**Step 3: Implement social_aggro/2**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex`:

```elixir
  @doc """
  Trigger social aggro - nearby creature joins combat against a target.

  Only affects idle creatures. Combat/evade/dead creatures ignore this.
  """
  @spec social_aggro(t(), non_neg_integer()) :: t()
  def social_aggro(%__MODULE__{state: :idle} = ai, target_guid) do
    enter_combat(ai, target_guid)
  end

  def social_aggro(%__MODULE__{} = ai, _target_guid), do: ai
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_aggro_test.exs
git commit -m "feat(core): add AI.social_aggro/2 for group pulls"
```

---

## Task 9: Add Social Aggro Range Constant

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/creature_template.ex`

**Step 1: Add social aggro range field**

Add to the CreatureTemplate struct:

```elixir
  @social_aggro_range 10.0  # Default 10 meters for social aggro

  defstruct [
    # ... existing fields ...
    :social_aggro_range  # Range for pulling nearby same-faction creatures
  ]

  @doc """
  Get social aggro range, with default fallback.
  """
  @spec social_aggro_range(t()) :: float()
  def social_aggro_range(%__MODULE__{social_aggro_range: range}) when is_number(range), do: range
  def social_aggro_range(_), do: @social_aggro_range
```

**Step 2: Run compile**

Run: `mix compile`
Expected: SUCCESS

**Step 3: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/creature_template.ex
git commit -m "feat(core): add social_aggro_range to CreatureTemplate"
```

---

## Task 10: Trigger Social Aggro in CreatureManager

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`
- Test: `apps/bezgelor_world/test/creature_social_aggro_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_world/test/creature_social_aggro_test.exs`:

```elixir
defmodule BezgelorWorld.CreatureSocialAggroTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager

  setup do
    start_supervised!(CreatureManager)
    CreatureManager.clear_all()
    :ok
  end

  describe "social aggro" do
    test "nearby same-faction creatures join combat" do
      # Spawn two wolves near each other (same faction)
      {:ok, wolf1_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = CreatureManager.spawn_creature(2, {5.0, 0.0, 0.0})

      # Trigger combat for wolf1
      CreatureManager.creature_enter_combat(wolf1_guid, 0x1000000000000001)

      # Allow social aggro to propagate
      Process.sleep(50)

      # Wolf2 should also be in combat
      {:ok, wolf2_state} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_state.ai.state == :combat
    end

    test "distant creatures don't join combat" do
      # Spawn two wolves far apart
      {:ok, wolf1_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = CreatureManager.spawn_creature(2, {50.0, 0.0, 0.0})  # Far away

      # Trigger combat for wolf1
      CreatureManager.creature_enter_combat(wolf1_guid, 0x1000000000000001)
      Process.sleep(50)

      # Wolf2 should stay idle
      {:ok, wolf2_state} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_state.ai.state == :idle
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/creature_social_aggro_test.exs -v`
Expected: FAIL

**Step 3: Add social aggro trigger to creature_enter_combat**

Modify the `creature_enter_combat` handler in CreatureManager:

```elixir
  @impl true
  def handle_cast({:creature_enter_combat, creature_guid, target_guid}, state) do
    case Map.get(state.creatures, creature_guid) do
      nil ->
        {:noreply, state}

      creature_state ->
        # Enter combat
        new_ai = AI.enter_combat(creature_state.ai, target_guid)
        new_creature_state = %{creature_state | ai: new_ai}

        # Trigger social aggro for nearby same-faction creatures
        state = trigger_social_aggro(creature_state, target_guid, state)

        creatures = Map.put(state.creatures, creature_guid, new_creature_state)
        {:noreply, %{state | creatures: creatures}}
    end
  end

  # Trigger social aggro for nearby creatures of same faction
  defp trigger_social_aggro(aggressor_state, target_guid, state) do
    aggressor_faction = aggressor_state.template.faction_id || 0
    aggressor_pos = aggressor_state.entity.position
    social_range = CreatureTemplate.social_aggro_range(aggressor_state.template)

    # Find nearby creatures of same faction
    nearby_same_faction =
      state.creatures
      |> Enum.filter(fn {guid, cs} ->
        guid != aggressor_state.entity.guid and
          (cs.template.faction_id || 0) == aggressor_faction and
          cs.ai.state == :idle and
          AI.distance(aggressor_pos, cs.entity.position) <= social_range
      end)

    # Trigger social aggro for each
    Enum.reduce(nearby_same_faction, state, fn {guid, cs}, acc_state ->
      new_ai = AI.social_aggro(cs.ai, target_guid)
      Logger.debug("Social aggro: #{cs.entity.name} joining combat against #{target_guid}")
      new_cs = %{cs | ai: new_ai}
      creatures = Map.put(acc_state.creatures, guid, new_cs)
      %{acc_state | creatures: creatures}
    end)
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/creature_social_aggro_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex apps/bezgelor_world/test/creature_social_aggro_test.exs
git commit -m "feat(world): trigger social aggro for nearby same-faction creatures"
```

---

## Task 11: Add Leash Distance Check to Combat Tick

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_leash_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/ai_leash_test.exs`:

```elixir
defmodule BezgelorCore.AILeashTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "check_leash/2" do
    test "returns :evade when current position exceeds leash range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Creature moved 50 units from spawn (leash range 40)
      current_pos = {50.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :evade
    end

    test "returns :ok when within leash range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Creature 30 units from spawn (within 40 leash range)
      current_pos = {30.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end

    test "returns :ok when not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      current_pos = {100.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_leash_test.exs -v`
Expected: FAIL

**Step 3: Implement check_leash/3**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex`:

```elixir
  @doc """
  Check if creature should leash (return to spawn) based on distance.

  Only triggers when in combat and distance from spawn exceeds leash_range.
  """
  @spec check_leash(t(), {float(), float(), float()}, float()) :: :evade | :ok
  def check_leash(%__MODULE__{state: :combat, spawn_position: spawn_pos}, current_pos, leash_range) do
    if distance(spawn_pos, current_pos) > leash_range do
      :evade
    else
      :ok
    end
  end

  def check_leash(%__MODULE__{}, _current_pos, _leash_range), do: :ok
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_leash_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_leash_test.exs
git commit -m "feat(core): add AI.check_leash/3 for leash distance checking"
```

---

## Task 12: Integrate Leash Check into Combat Tick

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add leash check to combat AI processing**

Find the combat state handling in `process_creature_ai` and add leash check:

```elixir
  defp process_creature_ai(%{ai: %{state: :combat}} = creature_state, state) do
    # Check leash distance first
    current_pos = creature_state.entity.position
    leash_range = creature_state.template.leash_range || 40.0

    case AI.check_leash(creature_state.ai, current_pos, leash_range) do
      :evade ->
        # Start evading back to spawn
        new_ai = AI.start_evade(creature_state.ai)
        Logger.info("Creature #{creature_state.entity.name} leashing back to spawn")
        {:updated, %{creature_state | ai: new_ai}}

      :ok ->
        # Continue normal combat processing
        process_combat_tick(creature_state, state)
    end
  end

  # Extract existing combat tick logic
  defp process_combat_tick(creature_state, _state) do
    ai = creature_state.ai
    attack_speed = creature_state.template.attack_speed || 2000

    case AI.tick(ai, %{attack_speed: attack_speed}) do
      {:attack, target_guid} ->
        new_ai = AI.record_attack(ai)
        apply_creature_attack(creature_state.entity, creature_state.template, target_guid)
        {:updated, %{creature_state | ai: new_ai}}

      :none ->
        :unchanged
    end
  end
```

**Step 2: Run existing tests**

Run: `mix test apps/bezgelor_world/test/creature_manager_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): integrate leash distance check into combat tick"
```

---

## Task 13: Add Evade Movement to Spawn

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add evade state processing**

Add handler for evade state:

```elixir
  defp process_creature_ai(%{ai: %{state: :evade}} = creature_state, _state) do
    current_pos = creature_state.entity.position
    spawn_pos = creature_state.spawn_position

    # Check if reached spawn position
    if AI.distance(current_pos, spawn_pos) < 2.0 do
      # Complete evade - reset to idle, full heal
      new_ai = AI.complete_evade(creature_state.ai)
      healed_entity = %{creature_state.entity | health: creature_state.template.max_health}

      Logger.debug("Creature #{creature_state.entity.name} completed evade, resetting")
      {:updated, %{creature_state | ai: new_ai, entity: healed_entity}}
    else
      # Continue moving toward spawn
      # In future: broadcast movement to clients
      # For now, just teleport closer
      new_pos = move_toward(current_pos, spawn_pos, 5.0)  # Move 5 units toward spawn
      new_entity = %{creature_state.entity | position: new_pos}

      {:updated, %{creature_state | entity: new_entity}}
    end
  end

  # Helper to move position toward target
  defp move_toward({x1, y1, z1}, {x2, y2, z2}, distance) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    length = :math.sqrt(dx * dx + dy * dy + dz * dz)

    if length <= distance do
      {x2, y2, z2}  # Already close enough
    else
      ratio = distance / length
      {x1 + dx * ratio, y1 + dy * ratio, z1 + dz * ratio}
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/ -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): add evade movement back to spawn position"
```

---

## Task 14: Add Combat Timeout When Target Unreachable

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_aggro_test.exs`

**Step 1: Add test for combat timeout**

Add to `apps/bezgelor_core/test/ai_aggro_test.exs`:

```elixir
  describe "combat_timeout?/1" do
    test "returns true when combat exceeds timeout" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Simulate 31 seconds of combat (timeout is 30s)
      ai = %{ai | combat_start_time: System.monotonic_time(:millisecond) - 31_000}

      assert AI.combat_timeout?(ai) == true
    end

    test "returns false when combat within timeout" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Just started combat
      assert AI.combat_timeout?(ai) == false
    end

    test "returns false when not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      assert AI.combat_timeout?(ai) == false
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: FAIL

**Step 3: Implement combat_timeout?/1**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex`:

```elixir
  @combat_timeout_ms 30_000  # 30 seconds

  @doc """
  Check if combat has timed out (target unreachable or combat stale).
  """
  @spec combat_timeout?(t()) :: boolean()
  def combat_timeout?(%__MODULE__{state: :combat, combat_start_time: start_time})
      when is_integer(start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    elapsed >= @combat_timeout_ms
  end

  def combat_timeout?(%__MODULE__{}), do: false
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_aggro_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_aggro_test.exs
git commit -m "feat(core): add AI.combat_timeout?/1 for stale combat detection"
```

---

## Task 15: Check Combat Timeout in Combat Tick

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add timeout check to combat processing**

Update `process_creature_ai` for combat state to check timeout:

```elixir
  defp process_creature_ai(%{ai: %{state: :combat}} = creature_state, state) do
    # Check combat timeout first
    if AI.combat_timeout?(creature_state.ai) do
      Logger.debug("Creature #{creature_state.entity.name} combat timed out, evading")
      new_ai = AI.start_evade(creature_state.ai)
      {:updated, %{creature_state | ai: new_ai}}
    else
      # Check leash distance
      current_pos = creature_state.entity.position
      leash_range = creature_state.template.leash_range || 40.0

      case AI.check_leash(creature_state.ai, current_pos, leash_range) do
        :evade ->
          new_ai = AI.start_evade(creature_state.ai)
          Logger.info("Creature #{creature_state.entity.name} leashing back to spawn")
          {:updated, %{creature_state | ai: new_ai}}

        :ok ->
          process_combat_tick(creature_state, state)
      end
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/ -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): check combat timeout before combat tick processing"
```

---

## Task 16: Exit Combat When Target Dies

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add target death check**

Update `process_combat_tick` to check if target is still valid:

```elixir
  defp process_combat_tick(creature_state, state) do
    ai = creature_state.ai
    target_guid = ai.target_guid

    # Check if target still exists and is alive
    case check_target_valid(target_guid, creature_state.world_id) do
      :valid ->
        # Normal combat tick
        attack_speed = creature_state.template.attack_speed || 2000

        case AI.tick(ai, %{attack_speed: attack_speed}) do
          {:attack, ^target_guid} ->
            new_ai = AI.record_attack(ai)
            apply_creature_attack(creature_state.entity, creature_state.template, target_guid)
            {:updated, %{creature_state | ai: new_ai}}

          :none ->
            :unchanged
        end

      :dead ->
        # Target died, try to find new threat target or exit combat
        new_ai = AI.remove_threat_target(ai, target_guid)

        if AI.in_combat?(new_ai) do
          {:updated, %{creature_state | ai: new_ai}}
        else
          Logger.debug("Creature #{creature_state.entity.name} exiting combat, target dead")
          {:updated, %{creature_state | ai: AI.exit_combat(new_ai)}}
        end

      :not_found ->
        # Target gone, exit combat
        new_ai = AI.exit_combat(ai)
        {:updated, %{creature_state | ai: new_ai}}
    end
  end

  # Check if target entity is still valid
  defp check_target_valid(target_guid, world_id) do
    zone_key = {world_id, 1}

    case ZoneInstance.get_entity(zone_key, target_guid) do
      {:ok, entity} ->
        if entity.health > 0, do: :valid, else: :dead

      _ ->
        :not_found
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/ -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): exit combat when target dies or is unreachable"
```

---

## Task 17: Integration Test - Full Aggro Flow

**Files:**
- Create: `apps/bezgelor_world/test/integration/aggro_flow_test.exs`

**Step 1: Write comprehensive integration test**

Create `apps/bezgelor_world/test/integration/aggro_flow_test.exs`:

```elixir
defmodule BezgelorWorld.Integration.AggroFlowTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.{CreatureManager, ZoneInstance, TickScheduler}
  alias BezgelorCore.{Entity, AI}

  setup do
    # Start required services
    start_supervised!(TickScheduler)
    start_supervised!(CreatureManager)
    start_supervised!({ZoneInstance, zone_id: 1, instance_id: 1})

    CreatureManager.clear_all()
    :ok
  end

  describe "full aggro flow" do
    test "player enters zone, creature detects and attacks" do
      # 1. Spawn aggressive creature
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Verify starts idle
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle

      # 2. Add player to zone within aggro range
      player = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        name: "TestPlayer",
        position: {10.0, 0.0, 0.0},
        health: 1000,
        max_health: 1000,
        faction: :exile
      }
      ZoneInstance.add_entity({1, 1}, player)

      # 3. Wait for AI tick to detect player
      Process.sleep(1100)  # TickScheduler fires every 1000ms

      # 4. Verify creature entered combat
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.state == :combat
      assert state2.ai.target_guid == player.guid
    end

    test "creature leashes when player runs too far" do
      # Spawn creature
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Add and engage player
      player = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        position: {10.0, 0.0, 0.0},
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity({1, 1}, player)
      CreatureManager.creature_enter_combat(creature_guid, player.guid)

      # Move player far away
      ZoneInstance.update_entity({1, 1}, player.guid, fn p ->
        %{p | position: {100.0, 0.0, 0.0}}
      end)

      # Simulate creature following (moving away from spawn)
      CreatureManager.update_creature_position(creature_guid, {60.0, 0.0, 0.0})

      # Wait for tick to check leash
      Process.sleep(1100)

      # Verify creature started evading
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.state == :evade
    end

    test "social aggro pulls nearby creatures" do
      # Spawn two wolves near each other
      {:ok, wolf1} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)
      {:ok, wolf2} = CreatureManager.spawn_creature(2, {5.0, 0.0, 0.0}, world_id: 1)

      # Engage wolf1 directly
      CreatureManager.creature_enter_combat(wolf1, 0x1000000000000001)

      # Wolf2 should have been social aggro'd
      {:ok, state2} = CreatureManager.get_creature_state(wolf2)
      assert state2.ai.state == :combat
      assert state2.ai.target_guid == 0x1000000000000001
    end
  end
end
```

**Step 2: Run integration tests**

Run: `mix test apps/bezgelor_world/test/integration/aggro_flow_test.exs -v`
Expected: PASS (with possible adjustments for actual API)

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/integration/aggro_flow_test.exs
git commit -m "test(world): add aggro flow integration tests"
```

---

## Summary

This plan implements a complete aggro detection system with:

1. **Core Aggro Detection** (Tasks 1-4): Idle creatures detect players in `aggro_range` using spatial queries
2. **Faction Filtering** (Tasks 5-7): Only aggro hostile faction players
3. **Social Aggro** (Tasks 8-10): Nearby same-faction creatures join combat
4. **Leash Mechanics** (Tasks 11-13): Creatures evade back to spawn when pulled too far
5. **Combat Cleanup** (Tasks 14-16): Exit combat on timeout or target death
6. **Integration Tests** (Task 17): Full flow validation

### Key Integration Points

- `AI.check_aggro/3` and `AI.check_aggro_with_faction/4` for detection
- `CreatureManager.process_creature_ai/2` idle state handler for tick-based checking
- `Faction` module for hostility determination
- `AI.social_aggro/2` triggered on `creature_enter_combat`
- `AI.check_leash/3` in combat tick for leash distance
- `AI.combat_timeout?/1` for stale combat detection

Total: 17 tasks with TDD approach and atomic commits.
