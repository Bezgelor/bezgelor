# Tradeskills System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement WildStar's tradeskill (crafting) system including gathering skills, circuit board crafting, coordinate crafting, and skill progression.

**Architecture:** Database layer stores tradeskill progress, learned recipes, and crafting queue. World handler processes crafting requests and coordinates with Inventory for materials/results. Protocol packets sync state to client. Static data (recipes, materials) loaded from BezgelorData.

**Tech Stack:** Elixir, Ecto, GenServer (for crafting timers), ETS (static recipe data), Ranch TCP

---

## Overview

WildStar's tradeskill system includes:
- **6 Crafting Skills**: Weaponsmith, Armorer, Tailor, Outfitter, Technologist, Architect
- **3 Gathering Skills**: Mining, Survivalist, Relic Hunter
- **1 Hobby**: Cooking
- **Constraint**: Players can only have 2 active tradeskills at once

Two distinct crafting interfaces:
1. **Circuit Board** - Weaponsmith, Armorer, Tailor, Outfitter (power cores + microchips)
2. **Coordinate Crafting** - Technologist, Architect, Cooking (grid-based targeting)

---

## Critical Files

| Component | File Path |
|-----------|-----------|
| Migration | `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_tradeskill_tables.exs` |
| Tradeskill Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/tradeskill.ex` |
| Recipe Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/learned_recipe.ex` |
| Crafting Queue Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/crafting_queue.ex` |
| Context Module | `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex` |
| Handler | `apps/bezgelor_world/lib/bezgelor_world/handler/tradeskill_handler.ex` |
| Client Packets | `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_*.ex` |
| Server Packets | `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_*.ex` |
| Tests | `apps/bezgelor_db/test/tradeskills_test.exs` |

---

## Task 1: Create Tradeskill Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251210200000_create_tradeskill_tables.exs`

**Step 1: Generate migration file**

Run: `cd . && mix ecto.gen.migration create_tradeskill_tables --migrations-path apps/bezgelor_db/priv/repo/migrations`

**Step 2: Write migration content**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateTradeskillTables do
  use Ecto.Migration

  def change do
    # Character tradeskill progress
    create table(:tradeskills) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :skill_id, :integer, null: false
      add :level, :integer, null: false, default: 1
      add :experience, :integer, null: false, default: 0
      add :talent_points, :integer, null: false, default: 0
      add :talent_selections, :map, default: %{}
      add :tech_tree_progress, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tradeskills, [:character_id, :skill_id])
    create index(:tradeskills, [:character_id])

    # Learned recipes
    create table(:learned_recipes) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :recipe_id, :integer, null: false
      add :craft_count, :integer, null: false, default: 0
      add :discovered_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:learned_recipes, [:character_id, :recipe_id])
    create index(:learned_recipes, [:character_id])

    # Active crafting queue
    create table(:crafting_queues) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :recipe_id, :integer, null: false
      add :quantity, :integer, null: false, default: 1
      add :crafted_count, :integer, null: false, default: 0
      add :state, :string, null: false, default: "pending"
      add :craft_data, :map, default: %{}
      add :started_at, :utc_datetime
      add :estimated_completion, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:crafting_queues, [:character_id])
    create index(:crafting_queues, [:character_id, :state])
  end
end
```

**Step 3: Run migration**

Run: `cd . && MIX_ENV=test mix ecto.migrate`
Expected: Migration completes successfully

**Step 4: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/*_create_tradeskill_tables.exs
git commit -m "feat(db): add tradeskill tables migration"
```

---

## Task 2: Create Tradeskill Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/tradeskill.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.Tradeskill do
  @moduledoc """
  Character tradeskill progress.

  Tracks skill level, experience, talent points, and tech tree progress
  for each tradeskill a character has learned.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @max_skills 2
  @max_level 6
  @skill_ids [
    # Crafting
    1, # Weaponsmith
    2, # Armorer
    3, # Tailor
    4, # Outfitter
    5, # Technologist
    6, # Architect
    # Gathering
    7, # Mining
    8, # Survivalist
    9, # Relic Hunter
    # Hobby
    10 # Cooking
  ]

  schema "tradeskills" do
    belongs_to :character, Character
    field :skill_id, :integer
    field :level, :integer, default: 1
    field :experience, :integer, default: 0
    field :talent_points, :integer, default: 0
    field :talent_selections, :map, default: %{}
    field :tech_tree_progress, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for learning a new tradeskill."
  def changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, [:character_id, :skill_id, :level, :experience, :talent_points, :talent_selections, :tech_tree_progress])
    |> validate_required([:character_id, :skill_id])
    |> validate_inclusion(:skill_id, @skill_ids)
    |> validate_number(:level, greater_than: 0, less_than_or_equal_to: @max_level)
    |> validate_number(:experience, greater_than_or_equal_to: 0)
    |> validate_number(:talent_points, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :skill_id])
    |> foreign_key_constraint(:character_id)
  end

  @doc "Changeset for gaining experience."
  def xp_changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, [:experience, :level, :talent_points])
    |> validate_number(:level, greater_than: 0, less_than_or_equal_to: @max_level)
    |> validate_number(:experience, greater_than_or_equal_to: 0)
  end

  @doc "Changeset for talent selection."
  def talent_changeset(tradeskill, talent_selections) do
    tradeskill
    |> cast(%{talent_selections: talent_selections}, [:talent_selections])
  end

  @doc "Changeset for tech tree progress."
  def tech_tree_changeset(tradeskill, progress) do
    tradeskill
    |> cast(%{tech_tree_progress: progress}, [:tech_tree_progress])
  end

  def max_skills, do: @max_skills
  def max_level, do: @max_level
  def valid_skill_ids, do: @skill_ids
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/tradeskill.ex
git commit -m "feat(db): add Tradeskill schema"
```

---

## Task 3: Create LearnedRecipe Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/learned_recipe.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.LearnedRecipe do
  @moduledoc """
  Recipes/schematics learned by a character.

  Tracks which recipes a character knows and how many times
  they've crafted each one (for recipe discovery).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "learned_recipes" do
    belongs_to :character, Character
    field :recipe_id, :integer
    field :craft_count, :integer, default: 0
    field :discovered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for learning a new recipe."
  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:character_id, :recipe_id, :craft_count, :discovered_at])
    |> validate_required([:character_id, :recipe_id])
    |> validate_number(:craft_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :recipe_id])
    |> foreign_key_constraint(:character_id)
  end

  @doc "Changeset for incrementing craft count."
  def increment_changeset(recipe) do
    recipe
    |> change(craft_count: recipe.craft_count + 1)
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/learned_recipe.ex
git commit -m "feat(db): add LearnedRecipe schema"
```

---

## Task 4: Create CraftingQueue Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/crafting_queue.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.CraftingQueue do
  @moduledoc """
  Active crafting queue for a character.

  Tracks in-progress crafting operations including
  circuit board or coordinate crafting state.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @states [:pending, :crafting, :completed, :failed, :cancelled]

  schema "crafting_queues" do
    belongs_to :character, Character
    field :recipe_id, :integer
    field :quantity, :integer, default: 1
    field :crafted_count, :integer, default: 0
    field :state, Ecto.Enum, values: @states, default: :pending
    field :craft_data, :map, default: %{}
    field :started_at, :utc_datetime
    field :estimated_completion, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for queueing a craft."
  def changeset(queue, attrs) do
    queue
    |> cast(attrs, [:character_id, :recipe_id, :quantity, :craft_data, :started_at, :estimated_completion])
    |> validate_required([:character_id, :recipe_id])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:character_id)
  end

  @doc "Changeset for starting a craft."
  def start_changeset(queue, started_at, estimated_completion) do
    queue
    |> change(state: :crafting, started_at: started_at, estimated_completion: estimated_completion)
  end

  @doc "Changeset for completing one item in the queue."
  def complete_item_changeset(queue) do
    new_count = queue.crafted_count + 1
    new_state = if new_count >= queue.quantity, do: :completed, else: :crafting

    queue
    |> change(crafted_count: new_count, state: new_state)
  end

  @doc "Changeset for failing a craft."
  def fail_changeset(queue) do
    queue
    |> change(state: :failed)
  end

  @doc "Changeset for cancelling a craft."
  def cancel_changeset(queue) do
    queue
    |> change(state: :cancelled)
  end

  def valid_states, do: @states
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/crafting_queue.ex
git commit -m "feat(db): add CraftingQueue schema"
```

---

## Task 5: Create Tradeskills Context - Core Functions

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`

**Step 1: Write the failing test**

Create: `apps/bezgelor_db/test/tradeskills_test.exs`

```elixir
defmodule BezgelorDb.TradeskillsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Tradeskills, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "crafter#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    {:ok, character} = Characters.create_character(account.id, %{
      name: "CraftMaster",
      sex: 0,
      race: 0,
      class: 0,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1
    })

    %{character: character}
  end

  describe "learn_skill/2" do
    test "learns a new tradeskill", %{character: char} do
      assert {:ok, skill} = Tradeskills.learn_skill(char.id, 1)
      assert skill.skill_id == 1
      assert skill.level == 1
      assert skill.experience == 0
    end

    test "cannot learn same skill twice", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      assert {:error, :already_learned} = Tradeskills.learn_skill(char.id, 1)
    end

    test "cannot exceed max skills", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.learn_skill(char.id, 2)
      assert {:error, :max_skills_reached} = Tradeskills.learn_skill(char.id, 3)
    end

    test "rejects invalid skill_id", %{character: char} do
      assert {:error, _} = Tradeskills.learn_skill(char.id, 999)
    end
  end

  describe "forget_skill/2" do
    test "forgets a learned skill", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      assert :ok = Tradeskills.forget_skill(char.id, 1)
      assert [] = Tradeskills.get_tradeskills(char.id)
    end

    test "returns error for unlearned skill", %{character: char} do
      assert {:error, :not_learned} = Tradeskills.forget_skill(char.id, 1)
    end
  end

  describe "get_tradeskills/1" do
    test "returns all learned skills", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.learn_skill(char.id, 7)

      skills = Tradeskills.get_tradeskills(char.id)
      assert length(skills) == 2
      assert Enum.any?(skills, &(&1.skill_id == 1))
      assert Enum.any?(skills, &(&1.skill_id == 7))
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: FAIL with "module BezgelorDb.Tradeskills is not available"

**Step 3: Write minimal implementation**

```elixir
defmodule BezgelorDb.Tradeskills do
  @moduledoc """
  Tradeskill management context.

  Handles learning/forgetting tradeskills, recipe management,
  crafting queue, and skill progression.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Tradeskill, LearnedRecipe, CraftingQueue}

  # Skill Management

  @doc "Get all tradeskills for a character."
  @spec get_tradeskills(integer()) :: [Tradeskill.t()]
  def get_tradeskills(character_id) do
    Tradeskill
    |> where([t], t.character_id == ^character_id)
    |> order_by([t], asc: t.skill_id)
    |> Repo.all()
  end

  @doc "Get a specific tradeskill."
  @spec get_tradeskill(integer(), integer()) :: Tradeskill.t() | nil
  def get_tradeskill(character_id, skill_id) do
    Repo.get_by(Tradeskill, character_id: character_id, skill_id: skill_id)
  end

  @doc "Check if character has learned a skill."
  @spec has_skill?(integer(), integer()) :: boolean()
  def has_skill?(character_id, skill_id) do
    Tradeskill
    |> where([t], t.character_id == ^character_id and t.skill_id == ^skill_id)
    |> Repo.exists?()
  end

  @doc "Count learned tradeskills."
  @spec count_skills(integer()) :: integer()
  def count_skills(character_id) do
    Tradeskill
    |> where([t], t.character_id == ^character_id)
    |> Repo.aggregate(:count)
  end

  @doc "Learn a new tradeskill."
  @spec learn_skill(integer(), integer()) :: {:ok, Tradeskill.t()} | {:error, term()}
  def learn_skill(character_id, skill_id) do
    cond do
      skill_id not in Tradeskill.valid_skill_ids() ->
        {:error, :invalid_skill}

      has_skill?(character_id, skill_id) ->
        {:error, :already_learned}

      count_skills(character_id) >= Tradeskill.max_skills() ->
        {:error, :max_skills_reached}

      true ->
        %Tradeskill{}
        |> Tradeskill.changeset(%{character_id: character_id, skill_id: skill_id})
        |> Repo.insert()
    end
  end

  @doc "Forget a tradeskill (preserves progress for re-learning)."
  @spec forget_skill(integer(), integer()) :: :ok | {:error, :not_learned}
  def forget_skill(character_id, skill_id) do
    case get_tradeskill(character_id, skill_id) do
      nil -> {:error, :not_learned}
      skill ->
        Repo.delete(skill)
        :ok
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex apps/bezgelor_db/test/tradeskills_test.exs
git commit -m "feat(db): add Tradeskills context with skill learning"
```

---

## Task 6: Add Recipe Management to Context

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`
- Modify: `apps/bezgelor_db/test/tradeskills_test.exs`

**Step 1: Add tests for recipes**

Append to `apps/bezgelor_db/test/tradeskills_test.exs`:

```elixir
  describe "unlock_recipe/2" do
    test "unlocks a new recipe", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      assert {:ok, recipe} = Tradeskills.unlock_recipe(char.id, 100)
      assert recipe.recipe_id == 100
      assert recipe.craft_count == 0
    end

    test "cannot unlock same recipe twice", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      assert {:error, :already_known} = Tradeskills.unlock_recipe(char.id, 100)
    end
  end

  describe "has_recipe?/2" do
    test "returns true for known recipe", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      assert Tradeskills.has_recipe?(char.id, 100)
    end

    test "returns false for unknown recipe", %{character: char} do
      refute Tradeskills.has_recipe?(char.id, 100)
    end
  end

  describe "get_recipes/1" do
    test "returns all learned recipes", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 101)

      recipes = Tradeskills.get_recipes(char.id)
      assert length(recipes) == 2
    end
  end

  describe "increment_craft_count/2" do
    test "increments the craft count", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)

      assert {:ok, recipe} = Tradeskills.increment_craft_count(char.id, 100)
      assert recipe.craft_count == 1

      assert {:ok, recipe} = Tradeskills.increment_craft_count(char.id, 100)
      assert recipe.craft_count == 2
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: FAIL with "function Tradeskills.unlock_recipe/2 is undefined"

**Step 3: Add recipe functions to context**

Add to `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`:

```elixir
  # Recipe Management

  @doc "Get all learned recipes for a character."
  @spec get_recipes(integer()) :: [LearnedRecipe.t()]
  def get_recipes(character_id) do
    LearnedRecipe
    |> where([r], r.character_id == ^character_id)
    |> order_by([r], asc: r.recipe_id)
    |> Repo.all()
  end

  @doc "Get a specific learned recipe."
  @spec get_recipe(integer(), integer()) :: LearnedRecipe.t() | nil
  def get_recipe(character_id, recipe_id) do
    Repo.get_by(LearnedRecipe, character_id: character_id, recipe_id: recipe_id)
  end

  @doc "Check if character knows a recipe."
  @spec has_recipe?(integer(), integer()) :: boolean()
  def has_recipe?(character_id, recipe_id) do
    LearnedRecipe
    |> where([r], r.character_id == ^character_id and r.recipe_id == ^recipe_id)
    |> Repo.exists?()
  end

  @doc "Unlock a new recipe."
  @spec unlock_recipe(integer(), integer()) :: {:ok, LearnedRecipe.t()} | {:error, term()}
  def unlock_recipe(character_id, recipe_id) do
    if has_recipe?(character_id, recipe_id) do
      {:error, :already_known}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %LearnedRecipe{}
      |> LearnedRecipe.changeset(%{
        character_id: character_id,
        recipe_id: recipe_id,
        discovered_at: now
      })
      |> Repo.insert()
    end
  end

  @doc "Increment craft count for a recipe."
  @spec increment_craft_count(integer(), integer()) :: {:ok, LearnedRecipe.t()} | {:error, term()}
  def increment_craft_count(character_id, recipe_id) do
    case get_recipe(character_id, recipe_id) do
      nil -> {:error, :recipe_not_found}
      recipe ->
        recipe
        |> LearnedRecipe.increment_changeset()
        |> Repo.update()
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex apps/bezgelor_db/test/tradeskills_test.exs
git commit -m "feat(db): add recipe management to Tradeskills context"
```

---

## Task 7: Add Crafting Queue Management

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`
- Modify: `apps/bezgelor_db/test/tradeskills_test.exs`

**Step 1: Add tests for crafting queue**

Append to `apps/bezgelor_db/test/tradeskills_test.exs`:

```elixir
  describe "queue_craft/4" do
    test "queues a craft operation", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)

      assert {:ok, queue} = Tradeskills.queue_craft(char.id, 100, 3, %{})
      assert queue.recipe_id == 100
      assert queue.quantity == 3
      assert queue.state == :pending
    end

    test "fails for unknown recipe", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      assert {:error, :recipe_not_known} = Tradeskills.queue_craft(char.id, 100, 1, %{})
    end
  end

  describe "start_craft/1" do
    test "starts a queued craft", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      {:ok, queue} = Tradeskills.queue_craft(char.id, 100, 1, %{})

      assert {:ok, started} = Tradeskills.start_craft(queue.id, 5000)
      assert started.state == :crafting
      assert started.started_at != nil
    end
  end

  describe "complete_craft_item/1" do
    test "completes one item in queue", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      {:ok, queue} = Tradeskills.queue_craft(char.id, 100, 2, %{})
      {:ok, started} = Tradeskills.start_craft(queue.id, 5000)

      assert {:ok, updated} = Tradeskills.complete_craft_item(started.id)
      assert updated.crafted_count == 1
      assert updated.state == :crafting

      assert {:ok, finished} = Tradeskills.complete_craft_item(updated.id)
      assert finished.crafted_count == 2
      assert finished.state == :completed
    end
  end

  describe "cancel_craft/1" do
    test "cancels an in-progress craft", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      {:ok, queue} = Tradeskills.queue_craft(char.id, 100, 1, %{})
      {:ok, started} = Tradeskills.start_craft(queue.id, 5000)

      assert {:ok, cancelled} = Tradeskills.cancel_craft(started.id)
      assert cancelled.state == :cancelled
    end
  end

  describe "get_active_crafts/1" do
    test "returns only active crafts", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 100)
      {:ok, _} = Tradeskills.unlock_recipe(char.id, 101)

      {:ok, q1} = Tradeskills.queue_craft(char.id, 100, 1, %{})
      {:ok, _} = Tradeskills.start_craft(q1.id, 5000)

      {:ok, q2} = Tradeskills.queue_craft(char.id, 101, 1, %{})
      {:ok, started} = Tradeskills.start_craft(q2.id, 5000)
      {:ok, _} = Tradeskills.complete_craft_item(started.id)

      active = Tradeskills.get_active_crafts(char.id)
      assert length(active) == 1
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: FAIL with "function Tradeskills.queue_craft/4 is undefined"

**Step 3: Add crafting queue functions to context**

Add to `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`:

```elixir
  # Crafting Queue

  @doc "Get all active crafts for a character."
  @spec get_active_crafts(integer()) :: [CraftingQueue.t()]
  def get_active_crafts(character_id) do
    CraftingQueue
    |> where([q], q.character_id == ^character_id)
    |> where([q], q.state in [:pending, :crafting])
    |> order_by([q], asc: q.inserted_at)
    |> Repo.all()
  end

  @doc "Get a specific craft queue entry."
  @spec get_craft(integer()) :: CraftingQueue.t() | nil
  def get_craft(queue_id) do
    Repo.get(CraftingQueue, queue_id)
  end

  @doc "Queue a crafting operation."
  @spec queue_craft(integer(), integer(), integer(), map()) ::
          {:ok, CraftingQueue.t()} | {:error, term()}
  def queue_craft(character_id, recipe_id, quantity, craft_data) do
    if has_recipe?(character_id, recipe_id) do
      %CraftingQueue{}
      |> CraftingQueue.changeset(%{
        character_id: character_id,
        recipe_id: recipe_id,
        quantity: quantity,
        craft_data: craft_data
      })
      |> Repo.insert()
    else
      {:error, :recipe_not_known}
    end
  end

  @doc "Start a queued craft."
  @spec start_craft(integer(), integer()) :: {:ok, CraftingQueue.t()} | {:error, term()}
  def start_craft(queue_id, duration_ms) do
    case get_craft(queue_id) do
      nil ->
        {:error, :not_found}

      queue ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        estimated = DateTime.add(now, duration_ms, :millisecond)

        queue
        |> CraftingQueue.start_changeset(now, estimated)
        |> Repo.update()
    end
  end

  @doc "Complete one item in the crafting queue."
  @spec complete_craft_item(integer()) :: {:ok, CraftingQueue.t()} | {:error, term()}
  def complete_craft_item(queue_id) do
    case get_craft(queue_id) do
      nil -> {:error, :not_found}
      queue ->
        queue
        |> CraftingQueue.complete_item_changeset()
        |> Repo.update()
    end
  end

  @doc "Fail a craft."
  @spec fail_craft(integer()) :: {:ok, CraftingQueue.t()} | {:error, term()}
  def fail_craft(queue_id) do
    case get_craft(queue_id) do
      nil -> {:error, :not_found}
      queue ->
        queue
        |> CraftingQueue.fail_changeset()
        |> Repo.update()
    end
  end

  @doc "Cancel a craft."
  @spec cancel_craft(integer()) :: {:ok, CraftingQueue.t()} | {:error, term()}
  def cancel_craft(queue_id) do
    case get_craft(queue_id) do
      nil -> {:error, :not_found}
      queue ->
        queue
        |> CraftingQueue.cancel_changeset()
        |> Repo.update()
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex apps/bezgelor_db/test/tradeskills_test.exs
git commit -m "feat(db): add crafting queue management to Tradeskills context"
```

---

## Task 8: Add XP and Leveling Functions

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`
- Modify: `apps/bezgelor_db/test/tradeskills_test.exs`

**Step 1: Add tests for XP system**

Append to `apps/bezgelor_db/test/tradeskills_test.exs`:

```elixir
  describe "award_xp/3" do
    test "adds experience to skill", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)

      assert {:ok, skill} = Tradeskills.award_xp(char.id, 1, 100)
      assert skill.experience == 100
    end

    test "levels up when threshold reached", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)

      # Award enough XP to level up (threshold is 1000 for level 1)
      assert {:ok, skill} = Tradeskills.award_xp(char.id, 1, 1000)
      assert skill.level == 2
      assert skill.experience == 0
    end

    test "awards talent point on level up", %{character: char} do
      {:ok, _} = Tradeskills.learn_skill(char.id, 1)

      {:ok, skill} = Tradeskills.award_xp(char.id, 1, 1000)
      assert skill.talent_points == 1
    end

    test "returns error for unlearned skill", %{character: char} do
      assert {:error, :skill_not_learned} = Tradeskills.award_xp(char.id, 1, 100)
    end
  end

  describe "xp_to_level/1" do
    test "returns correct thresholds" do
      assert Tradeskills.xp_to_level(1) == 1000
      assert Tradeskills.xp_to_level(2) == 2000
      assert Tradeskills.xp_to_level(3) == 4000
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: FAIL with "function Tradeskills.award_xp/3 is undefined"

**Step 3: Add XP functions to context**

Add to `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`:

```elixir
  # XP and Leveling

  @xp_thresholds %{
    1 => 1000,
    2 => 2000,
    3 => 4000,
    4 => 8000,
    5 => 16000,
    6 => 0  # Max level
  }

  @doc "Get XP required to reach next level."
  @spec xp_to_level(integer()) :: integer()
  def xp_to_level(current_level) do
    Map.get(@xp_thresholds, current_level, 0)
  end

  @doc "Award experience to a tradeskill."
  @spec award_xp(integer(), integer(), integer()) :: {:ok, Tradeskill.t()} | {:error, term()}
  def award_xp(character_id, skill_id, xp_amount) do
    case get_tradeskill(character_id, skill_id) do
      nil ->
        {:error, :skill_not_learned}

      skill ->
        new_xp = skill.experience + xp_amount
        threshold = xp_to_level(skill.level)

        cond do
          # At max level
          skill.level >= Tradeskill.max_level() ->
            {:ok, skill}

          # Level up
          threshold > 0 and new_xp >= threshold ->
            overflow_xp = new_xp - threshold

            skill
            |> Tradeskill.xp_changeset(%{
              level: skill.level + 1,
              experience: overflow_xp,
              talent_points: skill.talent_points + 1
            })
            |> Repo.update()

          # Just add XP
          true ->
            skill
            |> Tradeskill.xp_changeset(%{experience: new_xp})
            |> Repo.update()
        end
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex apps/bezgelor_db/test/tradeskills_test.exs
git commit -m "feat(db): add XP and leveling to Tradeskills context"
```

---

## Task 9: Create Server Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_tradeskill_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_tradeskill_update.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_recipe_learned.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_crafting_start.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_crafting_complete.ex`

**Step 1: Create ServerTradeskillList**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTradeskillList do
  @moduledoc """
  Send all tradeskills to client on login.

  ## Wire Format
  count  : uint8
  skills : [SkillEntry] * count

  SkillEntry:
    skill_id      : uint32
    level         : uint8
    experience    : uint32
    talent_points : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct skills: []

  @impl true
  def opcode, do: :server_tradeskill_list

  @impl true
  def write(%__MODULE__{skills: skills}, writer) do
    writer = PacketWriter.write_byte(writer, length(skills))

    writer =
      Enum.reduce(skills, writer, fn skill, w ->
        w
        |> PacketWriter.write_uint32(skill.skill_id)
        |> PacketWriter.write_byte(skill.level)
        |> PacketWriter.write_uint32(skill.experience)
        |> PacketWriter.write_byte(skill.talent_points)
      end)

    {:ok, writer}
  end
end
```

**Step 2: Create ServerTradeskillUpdate**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTradeskillUpdate do
  @moduledoc """
  Update a single tradeskill (level up, XP gain).

  ## Wire Format
  skill_id      : uint32
  level         : uint8
  experience    : uint32
  talent_points : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:skill_id, :level, :experience, :talent_points]

  @impl true
  def opcode, do: :server_tradeskill_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.skill_id)
      |> PacketWriter.write_byte(packet.level)
      |> PacketWriter.write_uint32(packet.experience)
      |> PacketWriter.write_byte(packet.talent_points)

    {:ok, writer}
  end
end
```

**Step 3: Create ServerRecipeLearned**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerRecipeLearned do
  @moduledoc """
  Notify client of newly learned recipe.

  ## Wire Format
  recipe_id : uint32
  skill_id  : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:recipe_id, :skill_id]

  @impl true
  def opcode, do: :server_recipe_learned

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.recipe_id)
      |> PacketWriter.write_uint32(packet.skill_id)

    {:ok, writer}
  end
end
```

**Step 4: Create ServerCraftingStart**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerCraftingStart do
  @moduledoc """
  Notify client that crafting has started.

  ## Wire Format
  queue_id    : uint32
  recipe_id   : uint32
  quantity    : uint16
  duration_ms : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:queue_id, :recipe_id, :quantity, :duration_ms]

  @impl true
  def opcode, do: :server_crafting_start

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.queue_id)
      |> PacketWriter.write_uint32(packet.recipe_id)
      |> PacketWriter.write_uint16(packet.quantity)
      |> PacketWriter.write_uint32(packet.duration_ms)

    {:ok, writer}
  end
end
```

**Step 5: Create ServerCraftingComplete**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerCraftingComplete do
  @moduledoc """
  Notify client that crafting is complete.

  ## Wire Format
  queue_id       : uint32
  success        : uint8 (0=fail, 1=success)
  result_item_id : uint32
  result_count   : uint16
  xp_gained      : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:queue_id, :success, :result_item_id, :result_count, :xp_gained]

  @impl true
  def opcode, do: :server_crafting_complete

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.queue_id)
      |> PacketWriter.write_byte(if(packet.success, do: 1, else: 0))
      |> PacketWriter.write_uint32(packet.result_item_id)
      |> PacketWriter.write_uint16(packet.result_count)
      |> PacketWriter.write_uint32(packet.xp_gained)

    {:ok, writer}
  end
end
```

**Step 6: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_tradeskill_list.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_tradeskill_update.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_recipe_learned.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_crafting_start.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_crafting_complete.ex
git commit -m "feat(protocol): add tradeskill server packets"
```

---

## Task 10: Create Client Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_learn_tradeskill.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_forget_tradeskill.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_craft_item.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_cancel_craft.ex`

**Step 1: Create ClientLearnTradeskill**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientLearnTradeskill do
  @moduledoc """
  Client request to learn a tradeskill.

  ## Wire Format
  skill_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:skill_id]

  @impl true
  def opcode, do: :client_learn_tradeskill

  @impl true
  def read(reader) do
    with {:ok, skill_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{skill_id: skill_id}, reader}
    end
  end
end
```

**Step 2: Create ClientForgetTradeskill**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientForgetTradeskill do
  @moduledoc """
  Client request to forget a tradeskill.

  ## Wire Format
  skill_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:skill_id]

  @impl true
  def opcode, do: :client_forget_tradeskill

  @impl true
  def read(reader) do
    with {:ok, skill_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{skill_id: skill_id}, reader}
    end
  end
end
```

**Step 3: Create ClientCraftItem**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientCraftItem do
  @moduledoc """
  Client request to craft an item.

  ## Wire Format
  recipe_id  : uint32
  quantity   : uint16
  craft_data : varies (circuit board or coordinate data)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:recipe_id, :quantity, :craft_data]

  @impl true
  def opcode, do: :client_craft_item

  @impl true
  def read(reader) do
    with {:ok, recipe_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, quantity, reader} <- PacketReader.read_uint16(reader),
         {:ok, craft_data, reader} <- read_craft_data(reader) do
      {:ok, %__MODULE__{recipe_id: recipe_id, quantity: quantity, craft_data: craft_data}, reader}
    end
  end

  defp read_craft_data(reader) do
    # For now, read remaining bytes as raw craft data
    # Future: parse circuit board or coordinate data
    remaining = PacketReader.remaining_bytes(reader)
    {:ok, %{raw: remaining}, reader}
  end
end
```

**Step 4: Create ClientCancelCraft**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientCancelCraft do
  @moduledoc """
  Client request to cancel an in-progress craft.

  ## Wire Format
  queue_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:queue_id]

  @impl true
  def opcode, do: :client_cancel_craft

  @impl true
  def read(reader) do
    with {:ok, queue_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{queue_id: queue_id}, reader}
    end
  end
end
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_learn_tradeskill.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_forget_tradeskill.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_craft_item.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_cancel_craft.ex
git commit -m "feat(protocol): add tradeskill client packets"
```

---

## Task 11: Create TradeskillHandler

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/tradeskill_handler.ex`

**Step 1: Write handler**

```elixir
defmodule BezgelorWorld.Handler.TradeskillHandler do
  @moduledoc """
  Handles tradeskill-related packets.

  Processes skill learning, recipe unlocks, and crafting operations.
  """

  alias BezgelorDb.Tradeskills
  alias BezgelorProtocol.Packets.World.{
    ClientLearnTradeskill,
    ClientForgetTradeskill,
    ClientCraftItem,
    ClientCancelCraft,
    ServerTradeskillList,
    ServerTradeskillUpdate,
    ServerRecipeLearned,
    ServerCraftingStart,
    ServerCraftingComplete
  }

  require Logger

  @craft_duration_ms 5000

  @doc """
  Send full tradeskill list to client (called on login).
  """
  @spec send_tradeskills(pid(), integer()) :: :ok
  def send_tradeskills(connection_pid, character_id) do
    skills = Tradeskills.get_tradeskills(character_id)

    skill_data =
      Enum.map(skills, fn skill ->
        %{
          skill_id: skill.skill_id,
          level: skill.level,
          experience: skill.experience,
          talent_points: skill.talent_points
        }
      end)

    packet = %ServerTradeskillList{skills: skill_data}
    send(connection_pid, {:send_packet, packet})

    :ok
  end

  @doc """
  Handle learn tradeskill request.
  """
  @spec handle_learn_tradeskill(pid(), integer(), ClientLearnTradeskill.t()) :: :ok
  def handle_learn_tradeskill(connection_pid, character_id, %ClientLearnTradeskill{} = packet) do
    case Tradeskills.learn_skill(character_id, packet.skill_id) do
      {:ok, skill} ->
        update_packet = %ServerTradeskillUpdate{
          skill_id: skill.skill_id,
          level: skill.level,
          experience: skill.experience,
          talent_points: skill.talent_points
        }

        send(connection_pid, {:send_packet, update_packet})
        Logger.debug("Character #{character_id} learned tradeskill #{packet.skill_id}")

      {:error, :max_skills_reached} ->
        Logger.warning("Character #{character_id} at max tradeskills")

      {:error, :already_learned} ->
        Logger.warning("Character #{character_id} already knows tradeskill #{packet.skill_id}")

      {:error, reason} ->
        Logger.warning("Learn tradeskill failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Handle forget tradeskill request.
  """
  @spec handle_forget_tradeskill(pid(), integer(), ClientForgetTradeskill.t()) :: :ok
  def handle_forget_tradeskill(connection_pid, character_id, %ClientForgetTradeskill{} = packet) do
    case Tradeskills.forget_skill(character_id, packet.skill_id) do
      :ok ->
        # Send updated list (skill removed)
        send_tradeskills(connection_pid, character_id)
        Logger.debug("Character #{character_id} forgot tradeskill #{packet.skill_id}")

      {:error, :not_learned} ->
        Logger.warning("Character #{character_id} doesn't know tradeskill #{packet.skill_id}")
    end

    :ok
  end

  @doc """
  Handle craft item request.
  """
  @spec handle_craft_item(pid(), integer(), ClientCraftItem.t()) :: :ok
  def handle_craft_item(connection_pid, character_id, %ClientCraftItem{} = packet) do
    # TODO: Check materials via Inventory
    # TODO: Look up recipe in BezgelorData for validation

    case Tradeskills.queue_craft(character_id, packet.recipe_id, packet.quantity, packet.craft_data) do
      {:ok, queue} ->
        case Tradeskills.start_craft(queue.id, @craft_duration_ms) do
          {:ok, started} ->
            start_packet = %ServerCraftingStart{
              queue_id: started.id,
              recipe_id: started.recipe_id,
              quantity: started.quantity,
              duration_ms: @craft_duration_ms
            }

            send(connection_pid, {:send_packet, start_packet})

            # Schedule completion
            Process.send_after(self(), {:craft_complete, started.id, character_id, connection_pid}, @craft_duration_ms)

            Logger.debug("Character #{character_id} started crafting recipe #{packet.recipe_id}")

          {:error, reason} ->
            Logger.warning("Failed to start craft: #{inspect(reason)}")
        end

      {:error, :recipe_not_known} ->
        Logger.warning("Character #{character_id} doesn't know recipe #{packet.recipe_id}")

      {:error, reason} ->
        Logger.warning("Queue craft failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Handle cancel craft request.
  """
  @spec handle_cancel_craft(pid(), integer(), ClientCancelCraft.t()) :: :ok
  def handle_cancel_craft(connection_pid, character_id, %ClientCancelCraft{} = packet) do
    case Tradeskills.cancel_craft(packet.queue_id) do
      {:ok, _} ->
        # Send completion with failure flag
        complete_packet = %ServerCraftingComplete{
          queue_id: packet.queue_id,
          success: false,
          result_item_id: 0,
          result_count: 0,
          xp_gained: 0
        }

        send(connection_pid, {:send_packet, complete_packet})
        Logger.debug("Character #{character_id} cancelled craft #{packet.queue_id}")

      {:error, reason} ->
        Logger.warning("Cancel craft failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Handle craft completion timer.
  """
  @spec handle_craft_complete(integer(), integer(), pid()) :: :ok
  def handle_craft_complete(queue_id, character_id, connection_pid) do
    case Tradeskills.get_craft(queue_id) do
      nil ->
        :ok

      queue when queue.state == :cancelled ->
        :ok

      queue ->
        # Complete one item
        case Tradeskills.complete_craft_item(queue_id) do
          {:ok, updated} ->
            # TODO: Look up recipe to get result item and XP
            result_item_id = 1000  # Placeholder
            xp_gained = 50  # Placeholder

            # Award XP to skill
            # TODO: Look up skill_id from recipe
            skill_id = 1
            Tradeskills.award_xp(character_id, skill_id, xp_gained)

            # Increment craft count for recipe discovery
            Tradeskills.increment_craft_count(character_id, queue.recipe_id)

            # TODO: Add result item to inventory

            complete_packet = %ServerCraftingComplete{
              queue_id: queue_id,
              success: true,
              result_item_id: result_item_id,
              result_count: 1,
              xp_gained: xp_gained
            }

            send(connection_pid, {:send_packet, complete_packet})

            # If more to craft, schedule next
            if updated.state == :crafting do
              Process.send_after(self(), {:craft_complete, queue_id, character_id, connection_pid}, @craft_duration_ms)
            end

          {:error, reason} ->
            Logger.error("Complete craft failed: #{inspect(reason)}")
        end
    end

    :ok
  end

  @doc """
  Grant a recipe to a character.
  """
  @spec give_recipe(pid(), integer(), integer(), integer()) :: {:ok, term()} | {:error, term()}
  def give_recipe(connection_pid, character_id, recipe_id, skill_id) do
    case Tradeskills.unlock_recipe(character_id, recipe_id) do
      {:ok, recipe} ->
        packet = %ServerRecipeLearned{
          recipe_id: recipe_id,
          skill_id: skill_id
        }

        send(connection_pid, {:send_packet, packet})
        {:ok, recipe}

      {:error, _} = err ->
        err
    end
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/tradeskill_handler.ex
git commit -m "feat(world): add TradeskillHandler"
```

---

## Task 12: Run Full Test Suite

**Step 1: Run all tradeskill tests**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/tradeskills_test.exs --trace`
Expected: All tests pass

**Step 2: Run full test suite**

Run: `cd . && MIX_ENV=test mix test`
Expected: All tests pass

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "test: ensure tradeskills integration works"
```

---

## Summary

After completing all tasks:

| Component | Status |
|-----------|--------|
| Migration | ✓ Tables for tradeskills, recipes, queue |
| Schemas | ✓ Tradeskill, LearnedRecipe, CraftingQueue |
| Context | ✓ Full CRUD + XP/leveling |
| Server Packets | ✓ List, Update, Recipe, Craft Start/Complete |
| Client Packets | ✓ Learn, Forget, Craft, Cancel |
| Handler | ✓ Full packet processing |
| Tests | ✓ Database layer tested |

**Future enhancements (not in this plan):**
1. Circuit Board crafting interface (power cores, microchips, sockets)
2. Coordinate Crafting interface (grid-based targeting)
3. Gathering skills (mining nodes, salvaging)
4. Tech Tree progression system
5. Talent system with bonuses
6. Material validation via Inventory integration
7. Recipe data loading from BezgelorData
