# Combat Movement System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement creature chase behavior during combat so creatures move toward their targets, with proper melee/ranged positioning, speed-based movement, and client-synchronized animation via ServerEntityCommand packets.

**Architecture:** Extend the existing AI state machine to handle movement during combat. Use `Movement.direct_path/3` for chase paths, broadcast via `ServerEntityCommand.set_position_path`, and update entity positions in the zone instance. Melee creatures close to attack range, ranged creatures maintain optimal distance.

**Tech Stack:** Elixir/OTP, ServerEntityCommand packets, SpatialGrid for position queries, existing Movement module for path generation.

---

## Implementation Order

1. **Tasks 1-3: Combat Movement State** - Add `:chasing` sub-state to combat AI
2. **Tasks 4-6: Chase Path Generation** - Create direct paths toward targets
3. **Tasks 7-9: Movement Broadcasting** - Send ServerEntityCommand for combat movement
4. **Tasks 10-12: Melee vs Ranged Positioning** - Different positioning strategies
5. **Tasks 13-15: Movement Speed & Animation** - Speed-based movement timing
6. **Task 16: Integration Test** - Full chase flow validation

---

## Task 1: Add Combat Sub-States to AI

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_combat_movement_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/ai_combat_movement_test.exs`:

```elixir
defmodule BezgelorCore.AICombatMovementTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "combat_action/3" do
    test "returns :chase when target is out of attack range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      target_pos = {20.0, 0.0, 0.0}  # 20 units away
      attack_range = 5.0              # Melee range

      result = AI.combat_action(ai, target_pos, attack_range)

      assert result == {:chase, target_pos}
    end

    test "returns :attack when target is in attack range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      target_pos = {3.0, 0.0, 0.0}  # 3 units away
      attack_range = 5.0             # Within melee range

      result = AI.combat_action(ai, target_pos, attack_range)

      assert result == {:attack, 12345}
    end

    test "returns :none when not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      result = AI.combat_action(ai, {5.0, 0.0, 0.0}, 5.0)

      assert result == :none
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: FAIL with "function AI.combat_action/3 is undefined"

**Step 3: Implement combat_action/3**

Add to `apps/bezgelor_core/lib/bezgelor_core/ai.ex`:

```elixir
  @doc """
  Determine combat action based on target distance.

  Returns what the creature should do during its combat tick:
  - `{:chase, target_position}` - Move toward target
  - `{:attack, target_guid}` - Attack the target
  - `:none` - Not in combat

  ## Parameters

  - `ai` - The AI state (must be in combat)
  - `target_position` - Current position of the target
  - `attack_range` - Range at which creature can attack
  """
  @spec combat_action(t(), {float(), float(), float()}, float()) ::
          {:chase, {float(), float(), float()}} | {:attack, non_neg_integer()} | :none
  def combat_action(%__MODULE__{state: :combat, target_guid: target_guid, spawn_position: current_pos}, target_pos, attack_range) do
    dist = distance(current_pos, target_pos)

    if dist <= attack_range do
      {:attack, target_guid}
    else
      {:chase, target_pos}
    end
  end

  def combat_action(%__MODULE__{}, _target_pos, _attack_range), do: :none
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_combat_movement_test.exs
git commit -m "feat(core): add AI.combat_action/3 for chase vs attack decision"
```

---

## Task 2: Add Chase State Tracking to AI

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_combat_movement_test.exs`

**Step 1: Add test for chase state**

Add to `apps/bezgelor_core/test/ai_combat_movement_test.exs`:

```elixir
  describe "start_chase/3" do
    test "sets chase path and timing" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      path = [{0.0, 0.0, 0.0}, {5.0, 0.0, 0.0}, {10.0, 0.0, 0.0}]
      duration = 2000

      new_ai = AI.start_chase(ai, path, duration)

      assert new_ai.chase_path == path
      assert new_ai.chase_duration == duration
      assert new_ai.chase_start_time != nil
    end
  end

  describe "chasing?/1" do
    test "returns true when actively chasing" do
      ai = AI.new({0.0, 0.0, 0.0})
           |> AI.enter_combat(12345)
           |> AI.start_chase([{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}], 2000)

      assert AI.chasing?(ai) == true
    end

    test "returns false when not chasing" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      assert AI.chasing?(ai) == false
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: FAIL

**Step 3: Add chase fields and functions to AI**

Add to the AI struct:

```elixir
  defstruct [
    # ... existing fields ...
    # Combat movement
    :chase_path,
    :chase_start_time,
    :chase_duration
  ]
```

Add functions:

```elixir
  @doc """
  Start chasing a target with a given path.
  """
  @spec start_chase(t(), [{float(), float(), float()}], non_neg_integer()) :: t()
  def start_chase(%__MODULE__{state: :combat} = ai, path, duration) do
    %{ai |
      chase_path: path,
      chase_start_time: System.monotonic_time(:millisecond),
      chase_duration: duration
    }
  end

  def start_chase(%__MODULE__{} = ai, _path, _duration), do: ai

  @doc """
  Check if currently in a chase movement.
  """
  @spec chasing?(t()) :: boolean()
  def chasing?(%__MODULE__{chase_path: path, chase_start_time: start, chase_duration: duration})
      when is_list(path) and is_integer(start) and is_integer(duration) do
    elapsed = System.monotonic_time(:millisecond) - start
    elapsed < duration
  end

  def chasing?(%__MODULE__{}), do: false

  @doc """
  Complete chase movement (reached destination or target moved).
  """
  @spec complete_chase(t()) :: t()
  def complete_chase(%__MODULE__{} = ai) do
    %{ai |
      chase_path: nil,
      chase_start_time: nil,
      chase_duration: nil
    }
  end

  @doc """
  Get current position along chase path.
  """
  @spec get_chase_position(t()) :: {float(), float(), float()} | nil
  def get_chase_position(%__MODULE__{chase_path: path, chase_start_time: start, chase_duration: duration})
      when is_list(path) and is_integer(start) and is_integer(duration) do
    elapsed = System.monotonic_time(:millisecond) - start
    progress = min(elapsed / duration, 1.0)
    Movement.interpolate_path(path, progress)
  end

  def get_chase_position(%__MODULE__{}), do: nil
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_combat_movement_test.exs
git commit -m "feat(core): add chase state tracking to AI"
```

---

## Task 3: Update combat_action to Consider Active Chase

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/ai.ex`
- Test: `apps/bezgelor_core/test/ai_combat_movement_test.exs`

**Step 1: Add test for chase-in-progress behavior**

Add to test file:

```elixir
  describe "combat_action with active chase" do
    test "returns :wait when chase is in progress" do
      ai = AI.new({0.0, 0.0, 0.0})
           |> AI.enter_combat(12345)
           |> AI.start_chase([{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}], 5000)

      target_pos = {15.0, 0.0, 0.0}
      result = AI.combat_action(ai, target_pos, 5.0)

      assert result == :wait
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: FAIL

**Step 3: Update combat_action to check chase state**

Update the function:

```elixir
  def combat_action(%__MODULE__{state: :combat} = ai, target_pos, attack_range) do
    # If already chasing, wait for movement to complete
    if chasing?(ai) do
      :wait
    else
      current_pos = get_chase_position(ai) || ai.spawn_position
      dist = distance(current_pos, target_pos)

      if dist <= attack_range do
        {:attack, ai.target_guid}
      else
        {:chase, target_pos}
      end
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/ai_combat_movement_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/ai.ex apps/bezgelor_core/test/ai_combat_movement_test.exs
git commit -m "feat(core): combat_action returns :wait during active chase"
```

---

## Task 4: Create Chase Path Generator

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/movement.ex`
- Test: `apps/bezgelor_core/test/movement_chase_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_core/test/movement_chase_test.exs`:

```elixir
defmodule BezgelorCore.MovementChaseTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Movement

  describe "chase_path/3" do
    test "generates path toward target stopping at attack range" do
      current = {0.0, 0.0, 0.0}
      target = {20.0, 0.0, 0.0}
      attack_range = 5.0

      path = Movement.chase_path(current, target, attack_range)

      # Path should end at attack range from target
      {end_x, _, _} = List.last(path)
      assert_in_delta end_x, 15.0, 0.5  # 20 - 5 = 15
    end

    test "returns empty path if already in range" do
      current = {3.0, 0.0, 0.0}
      target = {5.0, 0.0, 0.0}
      attack_range = 5.0

      path = Movement.chase_path(current, target, attack_range)

      assert path == []
    end

    test "path has waypoints every 2 units" do
      current = {0.0, 0.0, 0.0}
      target = {10.0, 0.0, 0.0}
      attack_range = 2.0

      path = Movement.chase_path(current, target, attack_range)

      # Should have ~4 waypoints for 8 unit travel
      assert length(path) >= 3
      assert length(path) <= 5
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/movement_chase_test.exs -v`
Expected: FAIL

**Step 3: Implement chase_path/3**

Add to `apps/bezgelor_core/lib/bezgelor_core/movement.ex`:

```elixir
  @doc """
  Generate a chase path toward a target, stopping at attack range.

  ## Parameters

  - `current_pos` - Current position of the chaser
  - `target_pos` - Position of the target
  - `attack_range` - Distance at which to stop (attack range)
  - `opts` - Options:
    - `:step_size` - Distance between waypoints (default 2.0)

  ## Returns

  List of waypoints from current position to attack range distance from target.
  Returns empty list if already in range.
  """
  @spec chase_path({float(), float(), float()}, {float(), float(), float()}, float(), keyword()) ::
          [{float(), float(), float()}]
  def chase_path(current_pos, target_pos, attack_range, opts \\ []) do
    step_size = Keyword.get(opts, :step_size, @step_size)

    {cx, cy, cz} = current_pos
    {tx, ty, tz} = target_pos

    dx = tx - cx
    dy = ty - cy
    dz = tz - cz
    total_distance = :math.sqrt(dx * dx + dy * dy + dz * dz)

    # Already in range
    if total_distance <= attack_range do
      []
    else
      # Calculate stop point (attack_range distance from target)
      stop_distance = total_distance - attack_range

      # Normalize direction
      nx = dx / total_distance
      ny = dy / total_distance
      nz = dz / total_distance

      # Generate waypoints
      num_steps = ceil(stop_distance / step_size)

      0..num_steps
      |> Enum.map(fn step ->
        progress = min(step * step_size / stop_distance, 1.0)
        {
          cx + nx * stop_distance * progress,
          cy + ny * stop_distance * progress,
          cz + nz * stop_distance * progress
        }
      end)
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/movement_chase_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/movement.ex apps/bezgelor_core/test/movement_chase_test.exs
git commit -m "feat(core): add Movement.chase_path/3 for combat pursuit"
```

---

## Task 5: Add Attack Range to CreatureTemplate

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/creature_template.ex`

**Step 1: Add attack_range field**

Check if it exists, if not add to struct:

```elixir
  @melee_attack_range 5.0
  @ranged_attack_range 30.0

  defstruct [
    # ... existing fields ...
    :attack_range,      # Range at which creature can attack
    :is_ranged          # Whether creature uses ranged attacks
  ]

  @doc """
  Get attack range with appropriate default.
  """
  @spec attack_range(t()) :: float()
  def attack_range(%__MODULE__{attack_range: range}) when is_number(range), do: range
  def attack_range(%__MODULE__{is_ranged: true}), do: @ranged_attack_range
  def attack_range(_), do: @melee_attack_range
```

**Step 2: Run compile**

Run: `mix compile`
Expected: SUCCESS

**Step 3: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/creature_template.ex
git commit -m "feat(core): add attack_range to CreatureTemplate"
```

---

## Task 6: Calculate Movement Speed and Duration

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/creature_template.ex`
- Test: `apps/bezgelor_core/test/creature_template_test.exs`

**Step 1: Add test for movement duration**

Add to or create test file:

```elixir
defmodule BezgelorCore.CreatureTemplateTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.CreatureTemplate

  describe "movement_duration/2" do
    test "calculates duration based on distance and speed" do
      template = %CreatureTemplate{movement_speed: 5.0}  # 5 units/second

      # 10 unit path = 2 seconds = 2000ms
      duration = CreatureTemplate.movement_duration(template, 10.0)

      assert duration == 2000
    end

    test "uses default speed when not specified" do
      template = %CreatureTemplate{}

      duration = CreatureTemplate.movement_duration(template, 10.0)

      # Default ~4.0 units/sec -> 2500ms for 10 units
      assert duration > 0
    end
  end
end
```

**Step 2: Run test**

Run: `mix test apps/bezgelor_core/test/creature_template_test.exs -v`

**Step 3: Implement movement_duration/2**

Add to creature_template.ex:

```elixir
  @default_movement_speed 4.0  # Units per second

  @doc """
  Calculate movement duration in milliseconds for a given distance.
  """
  @spec movement_duration(t(), float()) :: non_neg_integer()
  def movement_duration(%__MODULE__{movement_speed: speed}, distance) when is_number(speed) and speed > 0 do
    round(distance / speed * 1000)
  end

  def movement_duration(%__MODULE__{}, distance) do
    round(distance / @default_movement_speed * 1000)
  end

  @doc """
  Get movement speed in units per second.
  """
  @spec movement_speed(t()) :: float()
  def movement_speed(%__MODULE__{movement_speed: speed}) when is_number(speed), do: speed
  def movement_speed(_), do: @default_movement_speed
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/creature_template_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/creature_template.ex apps/bezgelor_core/test/creature_template_test.exs
git commit -m "feat(core): add movement_duration/2 to CreatureTemplate"
```

---

## Task 7: Wire Chase Logic to CreatureManager Combat Tick

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Update process_combat_tick to handle chase**

Modify the combat tick processing:

```elixir
  defp process_combat_tick(creature_state, state) do
    ai = creature_state.ai
    target_guid = ai.target_guid
    template = creature_state.template

    # Get target position
    case get_target_position(target_guid, creature_state.world_id) do
      {:ok, target_pos} ->
        attack_range = CreatureTemplate.attack_range(template)
        current_pos = AI.get_chase_position(ai) || creature_state.entity.position

        case AI.combat_action(ai, target_pos, attack_range) do
          {:attack, ^target_guid} ->
            # In range - attack
            if AI.can_attack?(ai, template.attack_speed || 2000) do
              new_ai = AI.record_attack(ai) |> AI.complete_chase()
              apply_creature_attack(creature_state.entity, template, target_guid)
              {:updated, %{creature_state | ai: new_ai}}
            else
              :unchanged
            end

          {:chase, ^target_pos} ->
            # Out of range - start chasing
            start_chase_movement(creature_state, target_pos, state)

          :wait ->
            # Already chasing, update position
            update_chase_position(creature_state)

          :none ->
            :unchanged
        end

      :not_found ->
        # Target gone, exit combat handled elsewhere
        :unchanged
    end
  end

  # Start a chase movement toward target
  defp start_chase_movement(creature_state, target_pos, _state) do
    current_pos = creature_state.entity.position
    template = creature_state.template
    attack_range = CreatureTemplate.attack_range(template)

    path = Movement.chase_path(current_pos, target_pos, attack_range)

    if path != [] do
      path_length = Movement.path_length(path)
      duration = CreatureTemplate.movement_duration(template, path_length)
      speed = CreatureTemplate.movement_speed(template)

      # Start chase in AI
      new_ai = AI.start_chase(creature_state.ai, path, duration)

      # Broadcast movement to clients
      broadcast_creature_movement(
        creature_state.entity.guid,
        path,
        speed,
        creature_state.world_id
      )

      {:updated, %{creature_state | ai: new_ai}}
    else
      :unchanged
    end
  end

  # Update entity position during chase
  defp update_chase_position(creature_state) do
    case AI.get_chase_position(creature_state.ai) do
      nil ->
        :unchanged

      new_pos ->
        new_entity = %{creature_state.entity | position: new_pos}
        {:updated, %{creature_state | entity: new_entity}}
    end
  end

  # Get target entity position from zone
  defp get_target_position(target_guid, world_id) do
    zone_key = {world_id, 1}

    case ZoneInstance.get_entity(zone_key, target_guid) do
      {:ok, entity} -> {:ok, entity.position}
      _ -> :not_found
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_manager_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): wire chase logic to creature combat tick"
```

---

## Task 8: Test Chase Movement Integration

**Files:**
- Create: `apps/bezgelor_world/test/creature_chase_test.exs`

**Step 1: Write integration test**

```elixir
defmodule BezgelorWorld.CreatureChaseTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CreatureManager, ZoneInstance}
  alias BezgelorCore.Entity

  setup do
    start_supervised!(CreatureManager)
    start_supervised!({ZoneInstance, zone_id: 1, instance_id: 1})
    CreatureManager.clear_all()
    :ok
  end

  describe "chase movement" do
    test "creature chases player when out of attack range" do
      # Spawn creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Add player far away
      player = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        position: {30.0, 0.0, 0.0},  # 30 units away
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity({1, 1}, player)

      # Put creature in combat
      CreatureManager.creature_enter_combat(creature_guid, player.guid)

      # Trigger combat tick
      send(CreatureManager, {:tick, 1})
      Process.sleep(50)

      # Verify creature started chasing
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.chase_path != nil
      assert length(state.ai.chase_path) > 0
    end

    test "creature attacks when in range instead of chasing" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Add player within melee range
      player = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        position: {3.0, 0.0, 0.0},  # 3 units away (within 5.0 melee range)
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity({1, 1}, player)

      CreatureManager.creature_enter_combat(creature_guid, player.guid)

      # Trigger tick
      send(CreatureManager, {:tick, 1})
      Process.sleep(50)

      # Creature should NOT be chasing
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert state.ai.chase_path == nil
    end
  end
end
```

**Step 2: Run test**

Run: `mix test apps/bezgelor_world/test/creature_chase_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/creature_chase_test.exs
git commit -m "test(world): add creature chase movement tests"
```

---

## Task 9: Handle Chase Completion and Re-evaluation

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add chase completion check**

Update `update_chase_position`:

```elixir
  defp update_chase_position(creature_state) do
    ai = creature_state.ai

    # Check if chase is complete
    if not AI.chasing?(ai) do
      # Chase finished, complete and re-evaluate next tick
      new_ai = AI.complete_chase(ai)
      end_pos = List.last(ai.chase_path) || creature_state.entity.position
      new_entity = %{creature_state.entity | position: end_pos}
      {:updated, %{creature_state | ai: new_ai, entity: new_entity}}
    else
      # Still chasing, update current position
      case AI.get_chase_position(ai) do
        nil -> :unchanged
        new_pos ->
          new_entity = %{creature_state.entity | position: new_pos}
          {:updated, %{creature_state | entity: new_entity}}
      end
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_chase_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): handle chase completion and position update"
```

---

## Task 10: Add Ranged Creature Positioning

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/movement.ex`
- Test: `apps/bezgelor_core/test/movement_chase_test.exs`

**Step 1: Add test for ranged positioning**

Add to test file:

```elixir
  describe "ranged_position_path/4" do
    test "moves to optimal ranged distance" do
      current = {0.0, 0.0, 0.0}
      target = {30.0, 0.0, 0.0}
      min_range = 15.0
      max_range = 25.0

      path = Movement.ranged_position_path(current, target, min_range, max_range)

      # Should end at optimal distance (middle of range)
      {end_x, _, _} = List.last(path)
      optimal = 30.0 - (min_range + max_range) / 2  # ~10 units from origin
      assert_in_delta end_x, optimal, 2.0
    end

    test "backs away if too close" do
      current = {25.0, 0.0, 0.0}  # 5 units from target
      target = {30.0, 0.0, 0.0}
      min_range = 15.0
      max_range = 25.0

      path = Movement.ranged_position_path(current, target, min_range, max_range)

      # Should move backwards (lower x)
      {end_x, _, _} = List.last(path)
      assert end_x < 25.0
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/movement_chase_test.exs -v`
Expected: FAIL

**Step 3: Implement ranged_position_path/4**

Add to movement.ex:

```elixir
  @doc """
  Generate path for ranged creature to maintain optimal distance.

  Moves to the middle of the min/max range to maintain safe attack distance.
  Will move backward if too close to target.

  ## Parameters

  - `current_pos` - Current position
  - `target_pos` - Target position
  - `min_range` - Minimum safe distance
  - `max_range` - Maximum attack range

  ## Returns

  Path to optimal position (middle of min/max range from target).
  """
  @spec ranged_position_path({float(), float(), float()}, {float(), float(), float()}, float(), float()) ::
          [{float(), float(), float()}]
  def ranged_position_path(current_pos, target_pos, min_range, max_range) do
    {cx, cy, cz} = current_pos
    {tx, ty, tz} = target_pos

    dx = tx - cx
    dy = ty - cy
    dz = tz - cz
    current_distance = :math.sqrt(dx * dx + dy * dy + dz * dz)

    optimal_distance = (min_range + max_range) / 2

    cond do
      # Already in optimal zone
      current_distance >= min_range and current_distance <= max_range ->
        []

      # Too close - back away
      current_distance < min_range ->
        # Move in opposite direction
        nx = -dx / current_distance
        ny = -dy / current_distance
        nz = -dz / current_distance

        move_distance = optimal_distance - current_distance + (optimal_distance - min_range)

        generate_path_direction(current_pos, {nx, ny, nz}, abs(move_distance))

      # Too far - move closer
      current_distance > max_range ->
        chase_path(current_pos, target_pos, optimal_distance)
    end
  end

  # Generate path in a specific direction
  defp generate_path_direction({cx, cy, cz}, {nx, ny, nz}, distance) do
    num_steps = ceil(distance / @step_size)

    0..num_steps
    |> Enum.map(fn step ->
      progress = min(step * @step_size / distance, 1.0)
      {
        cx + nx * distance * progress,
        cy + ny * distance * progress,
        cz + nz * distance * progress
      }
    end)
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/movement_chase_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/movement.ex apps/bezgelor_core/test/movement_chase_test.exs
git commit -m "feat(core): add ranged_position_path for ranged creature positioning"
```

---

## Task 11: Integrate Ranged Positioning into Combat

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Update start_chase_movement for ranged**

```elixir
  defp start_chase_movement(creature_state, target_pos, _state) do
    current_pos = creature_state.entity.position
    template = creature_state.template

    path = if template.is_ranged do
      # Ranged creatures maintain distance
      min_range = (template.attack_range || 30.0) * 0.5
      max_range = template.attack_range || 30.0
      Movement.ranged_position_path(current_pos, target_pos, min_range, max_range)
    else
      # Melee creatures close to attack range
      attack_range = CreatureTemplate.attack_range(template)
      Movement.chase_path(current_pos, target_pos, attack_range)
    end

    if path != [] do
      path_length = Movement.path_length(path)
      duration = CreatureTemplate.movement_duration(template, path_length)
      speed = CreatureTemplate.movement_speed(template)

      new_ai = AI.start_chase(creature_state.ai, path, duration)

      broadcast_creature_movement(
        creature_state.entity.guid,
        path,
        speed,
        creature_state.world_id
      )

      {:updated, %{creature_state | ai: new_ai}}
    else
      :unchanged
    end
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/creature_chase_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): integrate ranged positioning into creature combat"
```

---

## Task 12: Add Ranged Combat Test

**Files:**
- Modify: `apps/bezgelor_world/test/creature_chase_test.exs`

**Step 1: Add ranged positioning test**

```elixir
  describe "ranged creature movement" do
    test "ranged creature backs away when target too close" do
      # Would need a ranged creature template (template ID for ranged mob)
      # For now, manually create a ranged creature state for testing

      # This test verifies the ranged positioning logic is wired correctly
      # Implementation depends on having ranged creature templates
    end
  end
```

**Step 2: Run test**

Run: `mix test apps/bezgelor_world/test/creature_chase_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/creature_chase_test.exs
git commit -m "test(world): add ranged creature movement test placeholder"
```

---

## Task 13: Ensure Movement Speed in Broadcast

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Verify broadcast_creature_movement uses proper speed**

Check the existing function includes speed parameter:

```elixir
  defp broadcast_creature_movement(creature_guid, path, speed, world_id) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand

    # Build path command with speed
    path_command = %{
      type: :set_position_path,
      positions: path,
      speed: speed,
      spline_type: :linear,
      spline_mode: :one_shot,
      blend: true
    }

    # Build full entity command
    command = ServerEntityCommand.new(creature_guid, [
      {:set_state, %{state_flags: 0x02}},  # Moving
      {:set_move_defaults, %{}},
      path_command
    ])

    # Serialize and broadcast
    packet_data = ServerEntityCommand.encode(command)
    ZoneInstance.broadcast({world_id, 1}, {:server_entity_command, packet_data})
  end
```

**Step 2: Run compile**

Run: `mix compile`
Expected: SUCCESS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): ensure movement speed in creature broadcast"
```

---

## Task 14: Add Movement Animation Stop on Attack

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Stop movement when attacking**

Update the attack branch in `process_combat_tick`:

```elixir
          {:attack, ^target_guid} ->
            if AI.can_attack?(ai, template.attack_speed || 2000) do
              # Stop any active movement
              if AI.chasing?(ai) do
                broadcast_creature_stop(creature_state.entity.guid, creature_state.world_id)
              end

              new_ai = AI.record_attack(ai) |> AI.complete_chase()
              apply_creature_attack(creature_state.entity, template, target_guid)
              {:updated, %{creature_state | ai: new_ai}}
            else
              :unchanged
            end
```

Add stop broadcast function:

```elixir
  defp broadcast_creature_stop(creature_guid, world_id) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand

    command = ServerEntityCommand.new(creature_guid, [
      {:set_state, %{state_flags: 0x00}},  # Stopped
      {:set_move_defaults, %{}}
    ])

    packet_data = ServerEntityCommand.encode(command)
    ZoneInstance.broadcast({world_id, 1}, {:server_entity_command, packet_data})
  end
```

**Step 2: Run tests**

Run: `mix test apps/bezgelor_world/test/ -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): stop creature movement animation on attack"
```

---

## Task 15: Add Facing/Rotation Toward Target

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/movement.ex`

**Step 1: Add rotation calculation**

```elixir
  @doc """
  Calculate rotation to face a target position.

  Returns rotation in radians (yaw around Y axis).
  """
  @spec rotation_toward({float(), float(), float()}, {float(), float(), float()}) :: float()
  def rotation_toward({cx, _cy, cz}, {tx, _ty, tz}) do
    dx = tx - cx
    dz = tz - cz
    :math.atan2(dx, dz)
  end
```

**Step 2: Run compile**

Run: `mix compile`
Expected: SUCCESS

**Step 3: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/movement.ex
git commit -m "feat(core): add Movement.rotation_toward for facing calculation"
```

---

## Task 16: Integration Test - Full Combat Movement Flow

**Files:**
- Create: `apps/bezgelor_world/test/integration/combat_movement_test.exs`

**Step 1: Write comprehensive test**

```elixir
defmodule BezgelorWorld.Integration.CombatMovementTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.{CreatureManager, ZoneInstance, TickScheduler}
  alias BezgelorCore.Entity

  setup do
    start_supervised!(TickScheduler)
    start_supervised!(CreatureManager)
    start_supervised!({ZoneInstance, zone_id: 1, instance_id: 1})
    CreatureManager.clear_all()
    :ok
  end

  describe "full combat movement flow" do
    test "creature chases, catches up, and attacks player" do
      # Spawn creature
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0}, world_id: 1)

      # Add player at distance
      player = %Entity{
        guid: 0x1000000000000001,
        type: :player,
        position: {20.0, 0.0, 0.0},
        health: 1000,
        max_health: 1000
      }
      ZoneInstance.add_entity({1, 1}, player)

      # Enter combat
      CreatureManager.creature_enter_combat(creature_guid, player.guid)

      # First tick - should start chasing
      send(CreatureManager, {:tick, 1})
      Process.sleep(50)

      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.chase_path != nil

      # Simulate time passing (chase complete)
      Process.sleep(state1.ai.chase_duration + 100)

      # Move player closer to where creature ended up
      ZoneInstance.update_entity({1, 1}, player.guid, fn p ->
        %{p | position: {18.0, 0.0, 0.0}}  # Close to creature
      end)

      # Next tick - should attack (now in range)
      send(CreatureManager, {:tick, 2})
      Process.sleep(50)

      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      # Should have completed chase and recorded attack
      assert state2.ai.chase_path == nil
      assert state2.ai.last_attack_time != nil
    end
  end
end
```

**Step 2: Run integration test**

Run: `mix test apps/bezgelor_world/test/integration/combat_movement_test.exs -v`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/integration/combat_movement_test.exs
git commit -m "test(world): add combat movement integration test"
```

---

## Summary

This plan implements creature combat movement with:

1. **Combat Sub-States** (Tasks 1-3): AI tracks chase vs attack decisions
2. **Chase Path Generation** (Tasks 4-6): Direct paths toward targets with attack range stop
3. **Movement Broadcasting** (Tasks 7-9): ServerEntityCommand packets for client animation
4. **Melee vs Ranged Positioning** (Tasks 10-12): Different positioning strategies by creature type
5. **Movement Speed & Animation** (Tasks 13-15): Proper speed, stop on attack, facing
6. **Integration Test** (Task 16): Full chase-attack flow validation

### Key Integration Points

- `AI.combat_action/3` decides chase vs attack based on distance
- `Movement.chase_path/3` generates pursuit paths
- `Movement.ranged_position_path/4` handles ranged positioning
- `CreatureManager.start_chase_movement/3` initiates chase and broadcasts
- `broadcast_creature_movement/4` sends ServerEntityCommand packets
- `AI.chasing?/1` and `AI.get_chase_position/1` track active movement

Total: 16 tasks with TDD approach and atomic commits.
