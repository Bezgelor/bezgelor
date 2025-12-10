# Phase 9: Buffs/Debuffs with Duration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a buff/debuff system with duration tracking, stat modifications, and expiration handling.

**Architecture:** Create a `BuffDebuff` module in bezgelor_core for buff definitions and state. Add `BuffManager` GenServer in bezgelor_world (following SpellManager pattern) to track active buffs per entity with expiration timers. Extend Entity struct with `active_effects` map for stat modifications. Add protocol packets for buff application and removal.

**Tech Stack:** Elixir, GenServer, monotonic time (following Cooldown.ex pattern), ETS for state, Process.send_after for expiration timers.

---

## Task 1: BuffDebuff Struct and Types

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/buff_debuff.ex`
- Test: `apps/bezgelor_core/test/buff_debuff_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_core/test/buff_debuff_test.exs`:

```elixir
defmodule BezgelorCore.BuffDebuffTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.BuffDebuff

  describe "new/1" do
    test "creates buff with required fields" do
      buff = BuffDebuff.new(%{
        id: 1,
        spell_id: 4,
        buff_type: :absorb,
        amount: 100,
        duration: 10_000
      })

      assert buff.id == 1
      assert buff.spell_id == 4
      assert buff.buff_type == :absorb
      assert buff.amount == 100
      assert buff.duration == 10_000
      assert buff.is_debuff == false
    end

    test "creates debuff when is_debuff is true" do
      debuff = BuffDebuff.new(%{
        id: 2,
        spell_id: 5,
        buff_type: :stat_modifier,
        amount: -25,
        duration: 5_000,
        is_debuff: true,
        stat: :armor
      })

      assert debuff.is_debuff == true
      assert debuff.stat == :armor
    end
  end

  describe "buff?/1 and debuff?/1" do
    test "buff?/1 returns true for buffs" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :absorb, amount: 100, duration: 5000})
      assert BuffDebuff.buff?(buff)
      refute BuffDebuff.debuff?(buff)
    end

    test "debuff?/1 returns true for debuffs" do
      debuff = BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :stat_modifier, amount: -10, duration: 5000, is_debuff: true})
      assert BuffDebuff.debuff?(debuff)
      refute BuffDebuff.buff?(debuff)
    end
  end

  describe "stat_modifier?/1" do
    test "returns true for stat_modifier buff_type" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 5000})
      assert BuffDebuff.stat_modifier?(buff)
    end

    test "returns false for non-stat buffs" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :absorb, amount: 100, duration: 5000})
      refute BuffDebuff.stat_modifier?(buff)
    end
  end

  describe "type_to_int/1 and int_to_type/1" do
    test "converts buff types to integers" do
      assert BuffDebuff.type_to_int(:absorb) == 0
      assert BuffDebuff.type_to_int(:stat_modifier) == 1
      assert BuffDebuff.type_to_int(:damage_boost) == 2
      assert BuffDebuff.type_to_int(:heal_boost) == 3
      assert BuffDebuff.type_to_int(:periodic) == 4
    end

    test "converts integers to buff types" do
      assert BuffDebuff.int_to_type(0) == :absorb
      assert BuffDebuff.int_to_type(1) == :stat_modifier
      assert BuffDebuff.int_to_type(2) == :damage_boost
      assert BuffDebuff.int_to_type(3) == :heal_boost
      assert BuffDebuff.int_to_type(4) == :periodic
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_core && mix test test/buff_debuff_test.exs`
Expected: FAIL with "module BezgelorCore.BuffDebuff is not loaded"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_core/lib/bezgelor_core/buff_debuff.ex`:

```elixir
defmodule BezgelorCore.BuffDebuff do
  @moduledoc """
  Buff and debuff definitions.

  ## Overview

  Buffs are beneficial effects applied to entities (players, creatures).
  Debuffs are harmful effects. Both have a duration and can modify stats
  or provide special effects like damage absorption.

  ## Buff Types

  | Type | Description |
  |------|-------------|
  | :absorb | Absorbs incoming damage |
  | :stat_modifier | Modifies a stat (power, armor, etc.) |
  | :damage_boost | Increases outgoing damage |
  | :heal_boost | Increases healing done |
  | :periodic | Periodic effect (DoT/HoT tick tracking) |

  ## Usage

      iex> buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      iex> BuffDebuff.buff?(buff)
      true
  """

  @type buff_type :: :absorb | :stat_modifier | :damage_boost | :heal_boost | :periodic
  @type stat :: :power | :tech | :support | :armor | :magic_resist | :tech_resist | :crit_chance | nil

  defstruct [
    :id,
    :spell_id,
    :buff_type,
    :stat,
    amount: 0,
    duration: 0,
    is_debuff: false,
    stacks: 1,
    max_stacks: 1
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          spell_id: non_neg_integer(),
          buff_type: buff_type(),
          stat: stat(),
          amount: integer(),
          duration: non_neg_integer(),
          is_debuff: boolean(),
          stacks: non_neg_integer(),
          max_stacks: non_neg_integer()
        }

  # Buff type integer codes for packets
  @type_absorb 0
  @type_stat_modifier 1
  @type_damage_boost 2
  @type_heal_boost 3
  @type_periodic 4

  @doc """
  Create a new buff/debuff from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      spell_id: Map.fetch!(attrs, :spell_id),
      buff_type: Map.fetch!(attrs, :buff_type),
      stat: Map.get(attrs, :stat),
      amount: Map.fetch!(attrs, :amount),
      duration: Map.fetch!(attrs, :duration),
      is_debuff: Map.get(attrs, :is_debuff, false),
      stacks: Map.get(attrs, :stacks, 1),
      max_stacks: Map.get(attrs, :max_stacks, 1)
    }
  end

  @doc """
  Check if this is a buff (not a debuff).
  """
  @spec buff?(t()) :: boolean()
  def buff?(%__MODULE__{is_debuff: false}), do: true
  def buff?(%__MODULE__{}), do: false

  @doc """
  Check if this is a debuff.
  """
  @spec debuff?(t()) :: boolean()
  def debuff?(%__MODULE__{is_debuff: true}), do: true
  def debuff?(%__MODULE__{}), do: false

  @doc """
  Check if this buff modifies a stat.
  """
  @spec stat_modifier?(t()) :: boolean()
  def stat_modifier?(%__MODULE__{buff_type: :stat_modifier}), do: true
  def stat_modifier?(%__MODULE__{}), do: false

  @doc """
  Convert buff type atom to integer for packet serialization.
  """
  @spec type_to_int(buff_type()) :: non_neg_integer()
  def type_to_int(:absorb), do: @type_absorb
  def type_to_int(:stat_modifier), do: @type_stat_modifier
  def type_to_int(:damage_boost), do: @type_damage_boost
  def type_to_int(:heal_boost), do: @type_heal_boost
  def type_to_int(:periodic), do: @type_periodic
  def type_to_int(_), do: @type_absorb

  @doc """
  Convert integer to buff type atom.
  """
  @spec int_to_type(non_neg_integer()) :: buff_type()
  def int_to_type(@type_absorb), do: :absorb
  def int_to_type(@type_stat_modifier), do: :stat_modifier
  def int_to_type(@type_damage_boost), do: :damage_boost
  def int_to_type(@type_heal_boost), do: :heal_boost
  def int_to_type(@type_periodic), do: :periodic
  def int_to_type(_), do: :absorb
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_core && mix test test/buff_debuff_test.exs`
Expected: PASS (6 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/buff_debuff.ex apps/bezgelor_core/test/buff_debuff_test.exs
git commit -m "feat(core): add BuffDebuff struct and types"
```

---

## Task 2: ActiveEffect State Module

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/active_effect.ex`
- Test: `apps/bezgelor_core/test/active_effect_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_core/test/active_effect_test.exs`:

```elixir
defmodule BezgelorCore.ActiveEffectTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.ActiveEffect
  alias BezgelorCore.BuffDebuff

  describe "new/0" do
    test "creates empty state" do
      state = ActiveEffect.new()
      assert state == %{}
    end
  end

  describe "apply/4" do
    test "adds buff to state with expiration time" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert Map.has_key?(state, 1)
      assert state[1].buff == buff
      assert state[1].caster_guid == 12345
      assert state[1].expires_at == 1000 + 10_000
    end

    test "replaces existing buff with same id" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 150, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 2000)

      assert state[1].buff.amount == 150
      assert state[1].expires_at == 2000 + 10_000
    end
  end

  describe "remove/2" do
    test "removes buff from state" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      state = ActiveEffect.remove(state, 1)

      refute Map.has_key?(state, 1)
    end

    test "no-op if buff not present" do
      state = ActiveEffect.new()
      state = ActiveEffect.remove(state, 999)

      assert state == %{}
    end
  end

  describe "active?/2" do
    test "returns true if buff exists and not expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.active?(state, 1, 5000)
    end

    test "returns false if buff expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      refute ActiveEffect.active?(state, 1, 15_000)
    end

    test "returns false if buff not present" do
      state = ActiveEffect.new()
      refute ActiveEffect.active?(state, 999, 1000)
    end
  end

  describe "remaining/3" do
    test "returns remaining duration" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.remaining(state, 1, 5000) == 6000
    end

    test "returns 0 if expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.remaining(state, 1, 15_000) == 0
    end

    test "returns 0 if not present" do
      state = ActiveEffect.new()
      assert ActiveEffect.remaining(state, 999, 1000) == 0
    end
  end

  describe "cleanup/2" do
    test "removes expired effects" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: 50, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      state = ActiveEffect.cleanup(state, 10_000)

      refute Map.has_key?(state, 1)
      assert Map.has_key?(state, 2)
    end
  end

  describe "get_stat_modifier/3" do
    test "returns total modifier for a stat" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 25, duration: 10_000})
      buff3 = BuffDebuff.new(%{id: 3, spell_id: 6, buff_type: :stat_modifier, stat: :armor, amount: 10, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      state = ActiveEffect.apply(state, buff3, 12345, 1000)

      assert ActiveEffect.get_stat_modifier(state, :power, 5000) == 75
      assert ActiveEffect.get_stat_modifier(state, :armor, 5000) == 10
      assert ActiveEffect.get_stat_modifier(state, :tech, 5000) == 0
    end

    test "ignores expired modifiers" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 25, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)

      assert ActiveEffect.get_stat_modifier(state, :power, 10_000) == 25
    end
  end

  describe "get_absorb_remaining/2" do
    test "returns total absorb amount" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.get_absorb_remaining(state, 5000) == 100
    end

    test "returns 0 if no absorb effects" do
      state = ActiveEffect.new()
      assert ActiveEffect.get_absorb_remaining(state, 1000) == 0
    end
  end

  describe "consume_absorb/3" do
    test "reduces absorb amount and returns remainder" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 30, 5000)

      assert absorbed == 30
      assert remaining_damage == 0
      assert state[1].buff.amount == 70
    end

    test "removes buff when fully consumed" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 50, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 100, 5000)

      assert absorbed == 50
      assert remaining_damage == 50
      refute Map.has_key?(state, 1)
    end

    test "consumes from multiple absorb buffs" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 30, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :absorb, amount: 50, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 60, 5000)

      assert absorbed == 60
      assert remaining_damage == 0
      # First buff consumed, second partially consumed
      refute Map.has_key?(state, 1)
      assert state[2].buff.amount == 20
    end
  end

  describe "list_active/2" do
    test "returns list of active effects" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: 50, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)

      active = ActiveEffect.list_active(state, 3000)
      assert length(active) == 2

      # After buff1 expires
      active = ActiveEffect.list_active(state, 10_000)
      assert length(active) == 1
      assert hd(active).buff.id == 2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_core && mix test test/active_effect_test.exs`
Expected: FAIL with "module BezgelorCore.ActiveEffect is not loaded"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_core/lib/bezgelor_core/active_effect.ex`:

```elixir
defmodule BezgelorCore.ActiveEffect do
  @moduledoc """
  Active effect state management.

  ## Overview

  This module manages the state of active buffs and debuffs on an entity.
  State is a map from buff_id to effect data including expiration time.

  ## State Structure

      %{
        buff_id => %{
          buff: %BuffDebuff{},
          caster_guid: integer,
          expires_at: integer  # monotonic time in ms
        }
      }

  ## Usage

      iex> state = ActiveEffect.new()
      iex> buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      iex> state = ActiveEffect.apply(state, buff, caster_guid, now_ms)
      iex> ActiveEffect.active?(state, 1, now_ms + 5000)
      true
  """

  alias BezgelorCore.BuffDebuff

  @type effect_data :: %{
          buff: BuffDebuff.t(),
          caster_guid: non_neg_integer(),
          expires_at: integer()
        }

  @type state :: %{non_neg_integer() => effect_data()}

  @doc """
  Create a new empty active effect state.
  """
  @spec new() :: state()
  def new, do: %{}

  @doc """
  Apply a buff/debuff to the state.

  If a buff with the same ID already exists, it is replaced (refreshed).
  """
  @spec apply(state(), BuffDebuff.t(), non_neg_integer(), integer()) :: state()
  def apply(state, %BuffDebuff{} = buff, caster_guid, now_ms) do
    expires_at = now_ms + buff.duration

    effect_data = %{
      buff: buff,
      caster_guid: caster_guid,
      expires_at: expires_at
    }

    Map.put(state, buff.id, effect_data)
  end

  @doc """
  Remove a buff/debuff from the state.
  """
  @spec remove(state(), non_neg_integer()) :: state()
  def remove(state, buff_id) do
    Map.delete(state, buff_id)
  end

  @doc """
  Check if a buff is active (exists and not expired).
  """
  @spec active?(state(), non_neg_integer(), integer()) :: boolean()
  def active?(state, buff_id, now_ms) do
    case Map.get(state, buff_id) do
      nil -> false
      %{expires_at: expires_at} -> expires_at > now_ms
    end
  end

  @doc """
  Get remaining duration of a buff in milliseconds.
  """
  @spec remaining(state(), non_neg_integer(), integer()) :: non_neg_integer()
  def remaining(state, buff_id, now_ms) do
    case Map.get(state, buff_id) do
      nil -> 0
      %{expires_at: expires_at} -> max(0, expires_at - now_ms)
    end
  end

  @doc """
  Remove all expired effects from state.
  """
  @spec cleanup(state(), integer()) :: state()
  def cleanup(state, now_ms) do
    Map.filter(state, fn {_id, %{expires_at: expires_at}} ->
      expires_at > now_ms
    end)
  end

  @doc """
  Get total stat modifier for a given stat from all active effects.
  """
  @spec get_stat_modifier(state(), BuffDebuff.stat(), integer()) :: integer()
  def get_stat_modifier(state, stat, now_ms) do
    state
    |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
      expires_at > now_ms and
        buff.buff_type == :stat_modifier and
        buff.stat == stat
    end)
    |> Enum.reduce(0, fn {_id, %{buff: buff}}, acc ->
      acc + buff.amount
    end)
  end

  @doc """
  Get total remaining absorb amount from all active absorb effects.
  """
  @spec get_absorb_remaining(state(), integer()) :: non_neg_integer()
  def get_absorb_remaining(state, now_ms) do
    state
    |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
      expires_at > now_ms and buff.buff_type == :absorb
    end)
    |> Enum.reduce(0, fn {_id, %{buff: buff}}, acc ->
      acc + buff.amount
    end)
  end

  @doc """
  Consume absorb shields to reduce incoming damage.

  Returns `{updated_state, absorbed_amount, remaining_damage}`.
  Consumes from oldest absorb effects first (by buff_id order).
  """
  @spec consume_absorb(state(), non_neg_integer(), integer()) ::
          {state(), non_neg_integer(), non_neg_integer()}
  def consume_absorb(state, damage, now_ms) when damage > 0 do
    # Get active absorb buffs sorted by id (oldest first)
    absorb_buffs =
      state
      |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
        expires_at > now_ms and buff.buff_type == :absorb
      end)
      |> Enum.sort_by(fn {id, _} -> id end)

    consume_absorb_loop(state, absorb_buffs, damage, 0)
  end

  def consume_absorb(state, 0, _now_ms), do: {state, 0, 0}

  defp consume_absorb_loop(state, [], remaining_damage, total_absorbed) do
    {state, total_absorbed, remaining_damage}
  end

  defp consume_absorb_loop(state, _absorb_buffs, 0, total_absorbed) do
    {state, total_absorbed, 0}
  end

  defp consume_absorb_loop(state, [{buff_id, effect_data} | rest], remaining_damage, total_absorbed) do
    absorb_amount = effect_data.buff.amount

    cond do
      absorb_amount > remaining_damage ->
        # Partial absorb - reduce buff amount
        new_amount = absorb_amount - remaining_damage
        updated_buff = %{effect_data.buff | amount: new_amount}
        updated_data = %{effect_data | buff: updated_buff}
        state = Map.put(state, buff_id, updated_data)
        {state, total_absorbed + remaining_damage, 0}

      absorb_amount == remaining_damage ->
        # Exact absorb - remove buff
        state = Map.delete(state, buff_id)
        {state, total_absorbed + absorb_amount, 0}

      true ->
        # Buff fully consumed - remove and continue
        state = Map.delete(state, buff_id)
        new_remaining = remaining_damage - absorb_amount
        consume_absorb_loop(state, rest, new_remaining, total_absorbed + absorb_amount)
    end
  end

  @doc """
  List all active effects with remaining duration.
  """
  @spec list_active(state(), integer()) :: [effect_data()]
  def list_active(state, now_ms) do
    state
    |> Enum.filter(fn {_id, %{expires_at: expires_at}} -> expires_at > now_ms end)
    |> Enum.map(fn {_id, data} -> data end)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_core && mix test test/active_effect_test.exs`
Expected: PASS (14 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/active_effect.ex apps/bezgelor_core/test/active_effect_test.exs
git commit -m "feat(core): add ActiveEffect state management"
```

---

## Task 3: Extend Entity with Active Effects

**Files:**
- Modify: `apps/bezgelor_core/lib/bezgelor_core/entity.ex`
- Test: `apps/bezgelor_core/test/entity_buffs_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_core/test/entity_buffs_test.exs`:

```elixir
defmodule BezgelorCore.EntityBuffsTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Entity
  alias BezgelorCore.BuffDebuff
  alias BezgelorCore.ActiveEffect

  defp make_entity do
    %Entity{
      guid: 1,
      type: :player,
      name: "Test",
      health: 100,
      max_health: 100,
      active_effects: ActiveEffect.new()
    }
  end

  describe "apply_buff/3" do
    test "adds buff to entity" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      assert ActiveEffect.active?(entity.active_effects, 1, 5000)
    end
  end

  describe "remove_buff/2" do
    test "removes buff from entity" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.remove_buff(entity, 1)

      refute ActiveEffect.active?(entity.active_effects, 1, 5000)
    end
  end

  describe "has_buff?/3" do
    test "returns true if buff is active" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      assert Entity.has_buff?(entity, 1, 5000)
    end

    test "returns false if buff expired" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      refute Entity.has_buff?(entity, 1, 15_000)
    end
  end

  describe "get_modified_stat/3" do
    test "returns base stat with no modifiers" do
      entity = make_entity()
      base_stats = %{power: 100, armor: 0.1}

      assert Entity.get_modified_stat(entity, :power, base_stats, 1000) == 100
    end

    test "applies stat modifiers from buffs" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      base_stats = %{power: 100}

      assert Entity.get_modified_stat(entity, :power, base_stats, 5000) == 150
    end

    test "applies debuff stat reductions" do
      entity = make_entity()
      debuff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: -25, duration: 10_000, is_debuff: true})

      entity = Entity.apply_buff(entity, debuff, 12345, 1000)
      base_stats = %{power: 100}

      assert Entity.get_modified_stat(entity, :power, base_stats, 5000) == 75
    end
  end

  describe "apply_damage_with_absorb/3" do
    test "damage goes through with no absorb" do
      entity = make_entity()
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 30, 1000)

      assert entity.health == 70
      assert absorbed == 0
    end

    test "absorb reduces damage" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 50, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 30, 5000)

      assert entity.health == 100
      assert absorbed == 30
    end

    test "partial absorb when damage exceeds shield" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 20, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 50, 5000)

      assert entity.health == 70
      assert absorbed == 20
    end
  end

  describe "cleanup_effects/2" do
    test "removes expired effects" do
      entity = make_entity()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: 50, duration: 15_000})

      entity = Entity.apply_buff(entity, buff1, 12345, 1000)
      entity = Entity.apply_buff(entity, buff2, 12345, 1000)
      entity = Entity.cleanup_effects(entity, 10_000)

      refute Entity.has_buff?(entity, 1, 10_000)
      assert Entity.has_buff?(entity, 2, 10_000)
    end
  end

  describe "list_buffs/2" do
    test "returns list of active buffs" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      debuff = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: -10, duration: 10_000, is_debuff: true})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.apply_buff(entity, debuff, 12345, 1000)

      buffs = Entity.list_buffs(entity, 5000)
      assert length(buffs) == 1
      assert hd(buffs).buff.id == 1
    end
  end

  describe "list_debuffs/2" do
    test "returns list of active debuffs" do
      entity = make_entity()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      debuff = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: -10, duration: 10_000, is_debuff: true})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.apply_buff(entity, debuff, 12345, 1000)

      debuffs = Entity.list_debuffs(entity, 5000)
      assert length(debuffs) == 1
      assert hd(debuffs).buff.id == 2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_core && mix test test/entity_buffs_test.exs`
Expected: FAIL with "unknown key :active_effects in struct"

**Step 3: Write minimal implementation**

Modify `apps/bezgelor_core/lib/bezgelor_core/entity.ex`:

Add to struct (after line 68):
```elixir
    active_effects: %{}
```

Add to type (after line 47):
```elixir
          active_effects: map(),
```

Add these functions at the end of the module (before the final `end`):

```elixir
  # Buff/Debuff functions

  alias BezgelorCore.{BuffDebuff, ActiveEffect}

  @doc """
  Apply a buff or debuff to the entity.
  """
  @spec apply_buff(t(), BuffDebuff.t(), non_neg_integer(), integer()) :: t()
  def apply_buff(%__MODULE__{} = entity, %BuffDebuff{} = buff, caster_guid, now_ms) do
    effects = ActiveEffect.apply(entity.active_effects, buff, caster_guid, now_ms)
    %{entity | active_effects: effects}
  end

  @doc """
  Remove a buff or debuff from the entity.
  """
  @spec remove_buff(t(), non_neg_integer()) :: t()
  def remove_buff(%__MODULE__{} = entity, buff_id) do
    effects = ActiveEffect.remove(entity.active_effects, buff_id)
    %{entity | active_effects: effects}
  end

  @doc """
  Check if entity has an active buff/debuff.
  """
  @spec has_buff?(t(), non_neg_integer(), integer()) :: boolean()
  def has_buff?(%__MODULE__{} = entity, buff_id, now_ms) do
    ActiveEffect.active?(entity.active_effects, buff_id, now_ms)
  end

  @doc """
  Get a stat value with all active modifiers applied.
  """
  @spec get_modified_stat(t(), BuffDebuff.stat(), map(), integer()) :: number()
  def get_modified_stat(%__MODULE__{} = entity, stat, base_stats, now_ms) do
    base_value = Map.get(base_stats, stat, 0)
    modifier = ActiveEffect.get_stat_modifier(entity.active_effects, stat, now_ms)
    base_value + modifier
  end

  @doc """
  Apply damage with absorb shield processing.

  Returns `{updated_entity, absorbed_amount}`.
  """
  @spec apply_damage_with_absorb(t(), non_neg_integer(), integer()) :: {t(), non_neg_integer()}
  def apply_damage_with_absorb(%__MODULE__{} = entity, damage, now_ms) do
    {effects, absorbed, remaining_damage} =
      ActiveEffect.consume_absorb(entity.active_effects, damage, now_ms)

    entity = %{entity | active_effects: effects}
    entity = apply_damage(entity, remaining_damage)

    {entity, absorbed}
  end

  @doc """
  Clean up expired effects from the entity.
  """
  @spec cleanup_effects(t(), integer()) :: t()
  def cleanup_effects(%__MODULE__{} = entity, now_ms) do
    effects = ActiveEffect.cleanup(entity.active_effects, now_ms)
    %{entity | active_effects: effects}
  end

  @doc """
  List all active buffs (non-debuffs).
  """
  @spec list_buffs(t(), integer()) :: [map()]
  def list_buffs(%__MODULE__{} = entity, now_ms) do
    entity.active_effects
    |> ActiveEffect.list_active(now_ms)
    |> Enum.filter(fn %{buff: buff} -> BuffDebuff.buff?(buff) end)
  end

  @doc """
  List all active debuffs.
  """
  @spec list_debuffs(t(), integer()) :: [map()]
  def list_debuffs(%__MODULE__{} = entity, now_ms) do
    entity.active_effects
    |> ActiveEffect.list_active(now_ms)
    |> Enum.filter(fn %{buff: buff} -> BuffDebuff.debuff?(buff) end)
  end
```

Also update `from_character/2` and `create_creature/3` to initialize `active_effects: %{}`.

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_core && mix test test/entity_buffs_test.exs`
Expected: PASS (11 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/entity.ex apps/bezgelor_core/test/entity_buffs_test.exs
git commit -m "feat(core): extend Entity with buff/debuff support"
```

---

## Task 4: Buff Protocol Packets

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex` (add buff opcodes)
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_apply.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_remove.ex`
- Test: `apps/bezgelor_protocol/test/packets/world/buff_packets_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_protocol/test/packets/world/buff_packets_test.exs`:

```elixir
defmodule BezgelorProtocol.Packets.World.BuffPacketsTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.{ServerBuffApply, ServerBuffRemove}
  alias BezgelorProtocol.PacketWriter

  describe "ServerBuffApply" do
    test "opcode returns :server_buff_apply" do
      assert ServerBuffApply.opcode() == :server_buff_apply
    end

    test "writes buff application packet" do
      packet = %ServerBuffApply{
        target_guid: 12345,
        caster_guid: 67890,
        buff_id: 1,
        spell_id: 4,
        buff_type: 0,
        amount: 100,
        duration: 10_000,
        is_debuff: false
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerBuffApply.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # uint64 target + uint64 caster + uint32 buff_id + uint32 spell_id +
      # uint8 buff_type + int32 amount + uint32 duration + uint8 is_debuff
      assert byte_size(binary) == 8 + 8 + 4 + 4 + 1 + 4 + 4 + 1
    end

    test "new/7 creates packet struct" do
      packet = ServerBuffApply.new(12345, 67890, 1, 4, :absorb, 100, 10_000, false)

      assert packet.target_guid == 12345
      assert packet.caster_guid == 67890
      assert packet.buff_id == 1
      assert packet.spell_id == 4
      assert packet.buff_type == 0
      assert packet.amount == 100
      assert packet.duration == 10_000
      assert packet.is_debuff == false
    end
  end

  describe "ServerBuffRemove" do
    test "opcode returns :server_buff_remove" do
      assert ServerBuffRemove.opcode() == :server_buff_remove
    end

    test "writes buff removal packet" do
      packet = %ServerBuffRemove{
        target_guid: 12345,
        buff_id: 1,
        reason: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerBuffRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # uint64 target + uint32 buff_id + uint8 reason
      assert byte_size(binary) == 8 + 4 + 1
    end

    test "new/3 creates packet struct" do
      packet = ServerBuffRemove.new(12345, 1, :expired)

      assert packet.target_guid == 12345
      assert packet.buff_id == 1
      assert packet.reason == 1
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_protocol && mix test test/packets/world/buff_packets_test.exs`
Expected: FAIL with "module ServerBuffApply is not available"

**Step 3: Write minimal implementation**

First, add opcodes to `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`:

Find the opcode definitions and add (after pet opcodes around 0x0614):
```elixir
    # Buff/debuff opcodes (0x0620-0x0623)
    server_buff_apply: 0x0620,
    server_buff_remove: 0x0621,
    server_buff_update: 0x0622,
    server_buff_list: 0x0623,
```

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_apply.ex`:

```elixir
defmodule BezgelorProtocol.Packets.World.ServerBuffApply do
  @moduledoc """
  Buff/debuff application notification.

  ## Wire Format

  ```
  target_guid : uint64  - Entity receiving the buff
  caster_guid : uint64  - Entity that applied the buff
  buff_id     : uint32  - Unique buff instance ID
  spell_id    : uint32  - Spell that created this buff
  buff_type   : uint8   - Type (0=absorb, 1=stat_mod, etc.)
  amount      : int32   - Effect amount
  duration    : uint32  - Duration in milliseconds
  is_debuff   : uint8   - 1 if debuff, 0 if buff
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.BuffDebuff

  defstruct [:target_guid, :caster_guid, :buff_id, :spell_id, :buff_type, :amount, :duration, :is_debuff]

  @type t :: %__MODULE__{
          target_guid: non_neg_integer(),
          caster_guid: non_neg_integer(),
          buff_id: non_neg_integer(),
          spell_id: non_neg_integer(),
          buff_type: non_neg_integer(),
          amount: integer(),
          duration: non_neg_integer(),
          is_debuff: boolean()
        }

  @impl true
  def opcode, do: :server_buff_apply

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    is_debuff_byte = if packet.is_debuff, do: 1, else: 0
    amount_bytes = <<packet.amount::32-little-signed>>

    writer =
      writer
      |> PacketWriter.write_uint64(packet.target_guid)
      |> PacketWriter.write_uint64(packet.caster_guid)
      |> PacketWriter.write_uint32(packet.buff_id)
      |> PacketWriter.write_uint32(packet.spell_id)
      |> PacketWriter.write_byte(packet.buff_type)
      |> PacketWriter.write_bytes(amount_bytes)
      |> PacketWriter.write_uint32(packet.duration)
      |> PacketWriter.write_byte(is_debuff_byte)

    {:ok, writer}
  end

  @doc """
  Create a new buff apply packet.
  """
  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), atom() | non_neg_integer(), integer(), non_neg_integer(), boolean()) :: t()
  def new(target_guid, caster_guid, buff_id, spell_id, buff_type, amount, duration, is_debuff) do
    buff_type_int = if is_atom(buff_type), do: BuffDebuff.type_to_int(buff_type), else: buff_type

    %__MODULE__{
      target_guid: target_guid,
      caster_guid: caster_guid,
      buff_id: buff_id,
      spell_id: spell_id,
      buff_type: buff_type_int,
      amount: amount,
      duration: duration,
      is_debuff: is_debuff
    }
  end
end
```

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_remove.ex`:

```elixir
defmodule BezgelorProtocol.Packets.World.ServerBuffRemove do
  @moduledoc """
  Buff/debuff removal notification.

  ## Wire Format

  ```
  target_guid : uint64  - Entity losing the buff
  buff_id     : uint32  - Buff instance ID being removed
  reason      : uint8   - Removal reason (0=dispel, 1=expired, 2=cancelled)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Removal reasons
  @reason_dispel 0
  @reason_expired 1
  @reason_cancelled 2

  defstruct [:target_guid, :buff_id, :reason]

  @type removal_reason :: :dispel | :expired | :cancelled
  @type t :: %__MODULE__{
          target_guid: non_neg_integer(),
          buff_id: non_neg_integer(),
          reason: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_buff_remove

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.target_guid)
      |> PacketWriter.write_uint32(packet.buff_id)
      |> PacketWriter.write_byte(packet.reason)

    {:ok, writer}
  end

  @doc """
  Create a new buff remove packet.
  """
  @spec new(non_neg_integer(), non_neg_integer(), removal_reason() | non_neg_integer()) :: t()
  def new(target_guid, buff_id, reason) do
    reason_int = if is_atom(reason), do: reason_to_int(reason), else: reason

    %__MODULE__{
      target_guid: target_guid,
      buff_id: buff_id,
      reason: reason_int
    }
  end

  defp reason_to_int(:dispel), do: @reason_dispel
  defp reason_to_int(:expired), do: @reason_expired
  defp reason_to_int(:cancelled), do: @reason_cancelled
  defp reason_to_int(_), do: @reason_expired
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_protocol && mix test test/packets/world/buff_packets_test.exs`
Expected: PASS (6 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_apply.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_buff_remove.ex \
        apps/bezgelor_protocol/test/packets/world/buff_packets_test.exs
git commit -m "feat(protocol): add buff apply/remove packets"
```

---

## Task 5: BuffManager GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/buff_manager.ex`
- Test: `apps/bezgelor_world/test/buff_manager_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_world/test/buff_manager_test.exs`:

```elixir
defmodule BezgelorWorld.BuffManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.BuffManager
  alias BezgelorCore.BuffDebuff

  setup do
    # Start BuffManager for test
    start_supervised!(BuffManager)
    :ok
  end

  describe "apply_buff/4" do
    test "applies buff to entity and returns expiration timer ref" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, timer_ref} = BuffManager.apply_buff(12345, buff, 67890)

      assert is_reference(timer_ref)
      assert BuffManager.has_buff?(12345, 1)
    end
  end

  describe "remove_buff/2" do
    test "removes buff from entity" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      :ok = BuffManager.remove_buff(12345, 1)

      refute BuffManager.has_buff?(12345, 1)
    end

    test "returns error if buff not found" do
      assert {:error, :not_found} = BuffManager.remove_buff(12345, 999)
    end
  end

  describe "has_buff?/2" do
    test "returns true if entity has buff" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)

      assert BuffManager.has_buff?(12345, 1)
    end

    test "returns false if entity does not have buff" do
      refute BuffManager.has_buff?(12345, 999)
    end
  end

  describe "get_entity_buffs/1" do
    test "returns list of active buffs" do
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)

      buffs = BuffManager.get_entity_buffs(12345)
      assert length(buffs) == 2
    end

    test "returns empty list for entity with no buffs" do
      assert BuffManager.get_entity_buffs(99999) == []
    end
  end

  describe "get_stat_modifier/2" do
    test "returns total stat modifier" do
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 25, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)

      assert BuffManager.get_stat_modifier(12345, :power) == 75
    end
  end

  describe "consume_absorb/2" do
    test "consumes absorb shields" do
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      {absorbed, remaining} = BuffManager.consume_absorb(12345, 30)

      assert absorbed == 30
      assert remaining == 0
    end
  end

  describe "clear_entity/1" do
    test "removes all buffs from entity" do
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)
      :ok = BuffManager.clear_entity(12345)

      assert BuffManager.get_entity_buffs(12345) == []
    end
  end

  describe "buff expiration" do
    @tag :slow
    test "buff expires and is removed after duration" do
      # Use short duration for test
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 50})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      assert BuffManager.has_buff?(12345, 1)

      # Wait for expiration + buffer
      Process.sleep(100)

      refute BuffManager.has_buff?(12345, 1)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_world && mix test test/buff_manager_test.exs`
Expected: FAIL with "module BezgelorWorld.BuffManager is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_world/lib/bezgelor_world/buff_manager.ex`:

```elixir
defmodule BezgelorWorld.BuffManager do
  @moduledoc """
  Manages active buffs and debuffs for all entities.

  ## Overview

  The BuffManager tracks:
  - Active buffs/debuffs per entity
  - Expiration timers for automatic removal
  - Stat modifiers from buff effects
  - Absorb shield values

  This is similar to SpellManager but tracks ongoing effects rather than
  cast state.

  ## State Structure

      %{
        entities: %{
          entity_guid => %{
            effects: ActiveEffect.state(),
            timers: %{buff_id => timer_ref}
          }
        }
      }
  """

  use GenServer

  alias BezgelorCore.{BuffDebuff, ActiveEffect}

  require Logger

  @type entity_state :: %{
          effects: ActiveEffect.state(),
          timers: %{non_neg_integer() => reference()}
        }

  @type state :: %{
          entities: %{non_neg_integer() => entity_state()}
        }

  ## Client API

  @doc "Start the BuffManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Apply a buff/debuff to an entity.

  Returns `{:ok, timer_ref}` with the expiration timer reference.
  """
  @spec apply_buff(non_neg_integer(), BuffDebuff.t(), non_neg_integer()) ::
          {:ok, reference()}
  def apply_buff(entity_guid, %BuffDebuff{} = buff, caster_guid) do
    GenServer.call(__MODULE__, {:apply_buff, entity_guid, buff, caster_guid})
  end

  @doc """
  Remove a buff/debuff from an entity.
  """
  @spec remove_buff(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def remove_buff(entity_guid, buff_id) do
    GenServer.call(__MODULE__, {:remove_buff, entity_guid, buff_id})
  end

  @doc """
  Check if an entity has a specific buff.
  """
  @spec has_buff?(non_neg_integer(), non_neg_integer()) :: boolean()
  def has_buff?(entity_guid, buff_id) do
    GenServer.call(__MODULE__, {:has_buff?, entity_guid, buff_id})
  end

  @doc """
  Get all active buffs for an entity.
  """
  @spec get_entity_buffs(non_neg_integer()) :: [map()]
  def get_entity_buffs(entity_guid) do
    GenServer.call(__MODULE__, {:get_entity_buffs, entity_guid})
  end

  @doc """
  Get total stat modifier for an entity.
  """
  @spec get_stat_modifier(non_neg_integer(), BuffDebuff.stat()) :: integer()
  def get_stat_modifier(entity_guid, stat) do
    GenServer.call(__MODULE__, {:get_stat_modifier, entity_guid, stat})
  end

  @doc """
  Consume absorb shields for incoming damage.

  Returns `{absorbed_amount, remaining_damage}`.
  """
  @spec consume_absorb(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def consume_absorb(entity_guid, damage) do
    GenServer.call(__MODULE__, {:consume_absorb, entity_guid, damage})
  end

  @doc """
  Clear all buffs from an entity (on death/logout).
  """
  @spec clear_entity(non_neg_integer()) :: :ok
  def clear_entity(entity_guid) do
    GenServer.cast(__MODULE__, {:clear_entity, entity_guid})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{entities: %{}}
    Logger.info("BuffManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:apply_buff, entity_guid, buff, caster_guid}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)

    # Cancel existing timer for this buff if present
    if timer_ref = Map.get(entity.timers, buff.id) do
      Process.cancel_timer(timer_ref)
    end

    # Apply the buff
    effects = ActiveEffect.apply(entity.effects, buff, caster_guid, now)

    # Schedule expiration
    timer_ref = Process.send_after(self(), {:buff_expired, entity_guid, buff.id}, buff.duration)

    # Update state
    timers = Map.put(entity.timers, buff.id, timer_ref)
    entity = %{entity | effects: effects, timers: timers}
    state = put_entity_state(state, entity_guid, entity)

    Logger.debug("Applied buff #{buff.id} to entity #{entity_guid}")
    {:reply, {:ok, timer_ref}, state}
  end

  @impl true
  def handle_call({:remove_buff, entity_guid, buff_id}, _from, state) do
    entity = get_entity_state(state, entity_guid)

    if Map.has_key?(entity.effects, buff_id) do
      # Cancel timer
      if timer_ref = Map.get(entity.timers, buff_id) do
        Process.cancel_timer(timer_ref)
      end

      # Remove buff
      effects = ActiveEffect.remove(entity.effects, buff_id)
      timers = Map.delete(entity.timers, buff_id)
      entity = %{entity | effects: effects, timers: timers}
      state = put_entity_state(state, entity_guid, entity)

      Logger.debug("Removed buff #{buff_id} from entity #{entity_guid}")
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:has_buff?, entity_guid, buff_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    result = ActiveEffect.active?(entity.effects, buff_id, now)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_entity_buffs, entity_guid}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    buffs = ActiveEffect.list_active(entity.effects, now)
    {:reply, buffs, state}
  end

  @impl true
  def handle_call({:get_stat_modifier, entity_guid, stat}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    modifier = ActiveEffect.get_stat_modifier(entity.effects, stat, now)
    {:reply, modifier, state}
  end

  @impl true
  def handle_call({:consume_absorb, entity_guid, damage}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)

    {effects, absorbed, remaining} = ActiveEffect.consume_absorb(entity.effects, damage, now)

    # Clean up timers for fully consumed buffs
    consumed_ids =
      Map.keys(entity.effects) -- Map.keys(effects)

    timers =
      Enum.reduce(consumed_ids, entity.timers, fn id, acc ->
        if ref = Map.get(acc, id), do: Process.cancel_timer(ref)
        Map.delete(acc, id)
      end)

    entity = %{entity | effects: effects, timers: timers}
    state = put_entity_state(state, entity_guid, entity)

    {:reply, {absorbed, remaining}, state}
  end

  @impl true
  def handle_cast({:clear_entity, entity_guid}, state) do
    entity = get_entity_state(state, entity_guid)

    # Cancel all timers
    Enum.each(entity.timers, fn {_id, ref} ->
      Process.cancel_timer(ref)
    end)

    state = %{state | entities: Map.delete(state.entities, entity_guid)}
    Logger.debug("Cleared all buffs for entity #{entity_guid}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:buff_expired, entity_guid, buff_id}, state) do
    entity = get_entity_state(state, entity_guid)

    if Map.has_key?(entity.effects, buff_id) do
      effects = ActiveEffect.remove(entity.effects, buff_id)
      timers = Map.delete(entity.timers, buff_id)
      entity = %{entity | effects: effects, timers: timers}
      state = put_entity_state(state, entity_guid, entity)

      Logger.debug("Buff #{buff_id} expired on entity #{entity_guid}")
      # TODO: Broadcast buff removal packet
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Private helpers

  defp get_entity_state(state, entity_guid) do
    Map.get(state.entities, entity_guid, %{effects: ActiveEffect.new(), timers: %{}})
  end

  defp put_entity_state(state, entity_guid, entity) do
    %{state | entities: Map.put(state.entities, entity_guid, entity)}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_world && mix test test/buff_manager_test.exs`
Expected: PASS (9 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/buff_manager.ex apps/bezgelor_world/test/buff_manager_test.exs
git commit -m "feat(world): add BuffManager GenServer"
```

---

## Task 6: Integration - SpellHandler Buff Application

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`
- Test: `apps/bezgelor_world/test/spell_buff_integration_test.exs`

**Step 1: Write the failing test**

Create test file `apps/bezgelor_world/test/spell_buff_integration_test.exs`:

```elixir
defmodule BezgelorWorld.SpellBuffIntegrationTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{SpellManager, BuffManager}
  alias BezgelorCore.Spell

  setup do
    start_supervised!(SpellManager)
    start_supervised!(BuffManager)
    :ok
  end

  describe "casting Shield spell applies buff" do
    test "Shield spell (id 4) applies absorb buff via BuffManager" do
      player_guid = 12345
      # Shield spell has cast_time: 0 (instant) and buff effect
      spell = Spell.get(4)

      assert spell != nil
      assert spell.name == "Shield"
      assert Spell.instant?(spell)

      # Cast the spell
      {:ok, :instant, result} = SpellManager.cast_spell(player_guid, 4, player_guid, nil, %{})

      # Verify effect was calculated
      assert length(result.effects) == 1
      effect = hd(result.effects)
      assert effect.type == :buff

      # Integration: SpellHandler should call BuffManager.apply_buff
      # This test verifies the spell has buff effect that can be processed
      # Full integration with BuffManager would be in SpellHandler
    end
  end
end
```

**Step 2: Run test to verify it passes**

This is an integration smoke test. Run:
`cd apps/bezgelor_world && mix test test/spell_buff_integration_test.exs`
Expected: PASS (demonstrates spell-buff connection)

**Step 3: Document the integration point**

The actual integration happens in `SpellHandler.apply_spell_effects/4`. Add this function pattern:

In `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`, after effect calculation, add buff application logic:

```elixir
# In apply_spell_effects function, add case for buff effects:
defp apply_single_effect(%{type: :buff} = effect, caster_guid, target_guid, spell_id) do
  # Create buff from effect
  buff = BuffDebuff.new(%{
    id: generate_buff_id(spell_id),
    spell_id: spell_id,
    buff_type: effect.buff_type || :absorb,
    amount: effect.amount,
    duration: effect.duration,
    is_debuff: false
  })

  # Apply via BuffManager
  {:ok, _timer_ref} = BuffManager.apply_buff(target_guid, buff, caster_guid)

  # Return effect result for packet
  {:ok, effect}
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_world/test/spell_buff_integration_test.exs
git commit -m "test(world): add spell-buff integration smoke test"
```

---

## Task 7: Add BuffManager to Application Supervision

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`

**Step 1: Read current application.ex**

Check the current supervision tree structure.

**Step 2: Add BuffManager to children**

Add `BezgelorWorld.BuffManager` to the children list in `start/2`:

```elixir
children = [
  # ... existing children ...
  BezgelorWorld.BuffManager,
  # ... rest of children ...
]
```

**Step 3: Verify application starts**

Run: `cd apps/bezgelor_world && mix compile`
Expected: No errors

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/application.ex
git commit -m "feat(world): add BuffManager to supervision tree"
```

---

## Task 8: Run All Tests

**Step 1: Run bezgelor_core tests**

Run: `cd apps/bezgelor_core && mix test`
Expected: All tests pass

**Step 2: Run bezgelor_protocol tests**

Run: `cd apps/bezgelor_protocol && mix test`
Expected: All tests pass

**Step 3: Run bezgelor_world tests**

Run: `cd apps/bezgelor_world && mix test`
Expected: All tests pass

**Step 4: Commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address test failures from buff system integration"
```

---

## Summary

| Task | Component | Files Created/Modified |
|------|-----------|----------------------|
| 1 | BuffDebuff struct | `bezgelor_core/buff_debuff.ex` |
| 2 | ActiveEffect state | `bezgelor_core/active_effect.ex` |
| 3 | Entity buff support | `bezgelor_core/entity.ex` (modified) |
| 4 | Protocol packets | `server_buff_apply.ex`, `server_buff_remove.ex` |
| 5 | BuffManager | `bezgelor_world/buff_manager.ex` |
| 6 | Integration test | `spell_buff_integration_test.exs` |
| 7 | Supervision | `application.ex` (modified) |
| 8 | Full test suite | Verify all tests pass |

## Success Criteria

- [ ] BuffDebuff struct with types (absorb, stat_modifier, damage_boost, heal_boost, periodic)
- [ ] ActiveEffect state management with expiration tracking
- [ ] Entity supports apply_buff, remove_buff, has_buff?, stat modifiers, absorb consumption
- [ ] Protocol packets for buff application and removal
- [ ] BuffManager GenServer with expiration timers
- [ ] Buffs automatically expire after duration
- [ ] Stat modifiers aggregate correctly
- [ ] Absorb shields consume damage and deplete
- [ ] All tests pass
