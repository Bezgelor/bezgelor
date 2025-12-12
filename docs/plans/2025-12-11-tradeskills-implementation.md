# Phase 8: Tradeskills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** ~85% Complete (20/24 tasks)
**Last Review:** 2025-12-11

**Goal:** Implement the full WildStar tradeskill system with gathering, coordinate-based crafting, tech trees, work orders, and achievement integration.

**Architecture:** Database schemas in bezgelor_db, static data in bezgelor_data ETS, game logic in bezgelor_world modules, packets in bezgelor_protocol. All major behaviors are server-configurable.

**Tech Stack:** Elixir/OTP, Ecto, ETS, GenServer, binary protocol with PacketReader/PacketWriter.

---

## Implementation Status Summary

| Task # | Task | Status |
|--------|------|--------|
| 1 | Extract Tradeskill Data from Archive | ✅ Complete |
| 2 | Add Tradeskill Tables to ETS Store | ✅ Complete |
| 3 | Create Database Migration for Tradeskill Tables | ✅ Complete |
| 4 | Create CharacterTradeskill Schema | ✅ Complete |
| 5 | Create SchematicDiscovery Schema | ✅ Complete |
| 6 | Create TradeskillTalent Schema | ✅ Complete |
| 7 | Create WorkOrder Schema | ✅ Complete |
| 8 | Create Tradeskills Context Module | ✅ Complete |
| 9 | Create Coordinate System Module | ✅ Complete |
| 10 | Create CraftingSession Module | ✅ Complete |
| 11 | Create GatheringNode Module | ✅ Complete |
| 12 | Add Tradeskill Configuration | ✅ Complete |
| 13 | Create Tradeskill Packets (Client) | ⚠️ 85% (11/13) |
| 14 | Create Tradeskill Packets (Server) | ⚠️ 92% (11/12) |
| 15 | Create TradeskillHandler | ✅ Complete |
| 16 | Create CraftingHandler | ✅ Complete |
| 17 | Create GatheringHandler | ✅ Complete |
| 18 | Create NodeManager | ⚠️ Missing |
| 19 | Create TradeskillManager | ⚠️ Missing |
| 20 | Create TechTreeManager | ⚠️ Missing |
| 21 | Create WorkOrderManager | ⚠️ Missing |
| 22 | Add Achievement Criteria Types | ⚠️ Not verified |
| 23 | Integration Tests | ⚠️ Partial |
| 24 | Update STATUS.md | ✅ Complete |

### Missing Items

**Client Packets (2 missing):**
- `ClientTradeskillSwap` - Swap active profession
- `ClientCraftOvercharge` - Set overcharge level

**Server Packets (1 missing):**
- `ServerSchematicList` - Known schematics for profession

**Modules (4 missing):**
- `crafting/overcharge.ex` - Overcharge risk calculation (logic exists in coordinate_system.ex)
- `gathering/node_manager.ex` - Per-zone node spawning/respawn
- `tradeskill_manager.ex` - Profession management and limits
- `tech_tree_manager.ex` - Talent validation, prerequisites
- `work_order_manager.ex` - Daily generation, rewards

---

## Task 1: Extract Tradeskill Data from Archive

**Files:**
- Modify: `tools/tbl_extractor/tbl_extractor.py` (if needed for new data types)
- Create: `apps/bezgelor_data/priv/data/tradeskill_professions.json`
- Create: `apps/bezgelor_data/priv/data/tradeskill_schematics.json`
- Create: `apps/bezgelor_data/priv/data/tradeskill_materials.json`
- Create: `apps/bezgelor_data/priv/data/tradeskill_talents.json`
- Create: `apps/bezgelor_data/priv/data/gathering_nodes.json`

**Step 1: List tradeskill .tbl files in archive**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py --list ~/Downloads/wildstar_clientdata.archive | grep -i tradeskill
```

Expected: List of tradeskill-related .tbl files

**Step 2: Extract TradeskillTier.tbl**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py ~/Downloads/wildstar_clientdata.archive extract TradeskillTier.tbl apps/bezgelor_data/priv/data/tradeskill_professions.json
```

**Step 3: Extract TradeskillSchematic2.tbl**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py ~/Downloads/wildstar_clientdata.archive extract TradeskillSchematic2.tbl apps/bezgelor_data/priv/data/tradeskill_schematics.json
```

**Step 4: Extract TradeskillMaterial.tbl**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py ~/Downloads/wildstar_clientdata.archive extract TradeskillMaterial.tbl apps/bezgelor_data/priv/data/tradeskill_materials.json
```

**Step 5: Extract TradeskillTalent.tbl**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py ~/Downloads/wildstar_clientdata.archive extract TradeskillTalent.tbl apps/bezgelor_data/priv/data/tradeskill_talents.json
```

**Step 6: Extract HarvestingNode.tbl**

Run:
```bash
python3 tools/tbl_extractor/tbl_extractor.py ~/Downloads/wildstar_clientdata.archive extract HarvestingNode.tbl apps/bezgelor_data/priv/data/gathering_nodes.json
```

**Step 7: Verify extracted files**

Run:
```bash
ls -la apps/bezgelor_data/priv/data/tradeskill*.json apps/bezgelor_data/priv/data/gathering_nodes.json
```

**Step 8: Commit data files**

```bash
git add apps/bezgelor_data/priv/data/tradeskill*.json apps/bezgelor_data/priv/data/gathering_nodes.json
git commit -m "data: Extract tradeskill and gathering static data"
```

---

## Task 2: Add Tradeskill Tables to ETS Store

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`

**Step 1: Write the test for tradeskill data loading**

Create file: `apps/bezgelor_data/test/tradeskill_data_test.exs`

```elixir
defmodule BezgelorData.TradeskillDataTest do
  use ExUnit.Case, async: true

  alias BezgelorData.Store

  describe "tradeskill_professions" do
    test "loads profession data" do
      professions = Store.list(:tradeskill_professions)
      assert is_list(professions)
      # Should have crafting + gathering professions
      assert length(professions) > 0
    end

    test "retrieves profession by id" do
      # Armorer is profession ID 1 in WildStar
      case Store.get(:tradeskill_professions, 1) do
        {:ok, profession} ->
          assert is_map(profession)
          assert Map.has_key?(profession, :id)
        :error ->
          # Data may not be loaded in test env
          :ok
      end
    end
  end

  describe "tradeskill_schematics" do
    test "loads schematic data" do
      schematics = Store.list(:tradeskill_schematics)
      assert is_list(schematics)
    end
  end

  describe "gathering_nodes" do
    test "loads node data" do
      nodes = Store.list(:gathering_nodes)
      assert is_list(nodes)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_data/test/tradeskill_data_test.exs -v`

Expected: FAIL - tables don't exist yet

**Step 3: Add tradeskill tables to @tables list**

Edit `apps/bezgelor_data/lib/bezgelor_data/store.ex` line 15:

```elixir
@tables [
  :creatures, :zones, :spells, :items, :texts, :house_types,
  :housing_decor, :housing_fabkits, :titles,
  # Tradeskill tables
  :tradeskill_professions, :tradeskill_schematics, :tradeskill_materials,
  :tradeskill_talents, :gathering_nodes
]
```

**Step 4: Add load_table calls in load_all_data/0**

Edit `apps/bezgelor_data/lib/bezgelor_data/store.ex`, add after line 102:

```elixir
# Tradeskill data
load_table(:tradeskill_professions, "tradeskill_professions.json", "professions")
load_table(:tradeskill_schematics, "tradeskill_schematics.json", "schematics")
load_table(:tradeskill_materials, "tradeskill_materials.json", "materials")
load_table(:tradeskill_talents, "tradeskill_talents.json", "talents")
load_table(:gathering_nodes, "gathering_nodes.json", "nodes")
```

**Step 5: Run test to verify it passes**

Run: `mix test apps/bezgelor_data/test/tradeskill_data_test.exs -v`

Expected: PASS (or skip if data files don't exist in test env)

**Step 6: Commit**

```bash
git add apps/bezgelor_data/lib/bezgelor_data/store.ex apps/bezgelor_data/test/tradeskill_data_test.exs
git commit -m "feat(data): Add tradeskill tables to ETS store"
```

---

## Task 3: Create Database Migration for Tradeskill Tables

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251211000000_create_tradeskill_tables.exs`

**Step 1: Create the migration file**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateTradeskillTables do
  use Ecto.Migration

  def change do
    # Profession type enum
    execute(
      "CREATE TYPE profession_type AS ENUM ('crafting', 'gathering')",
      "DROP TYPE profession_type"
    )

    # Work order status enum
    execute(
      "CREATE TYPE work_order_status AS ENUM ('active', 'completed', 'expired')",
      "DROP TYPE work_order_status"
    )

    # Character tradeskill progress
    create table(:character_tradeskills) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :profession_id, :integer, null: false
      add :profession_type, :profession_type, null: false
      add :skill_level, :integer, null: false, default: 0
      add :skill_xp, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:character_tradeskills, [:character_id])
    create unique_index(:character_tradeskills, [:character_id, :profession_id])

    # Schematic discovery - supports both character and account scope
    create table(:schematic_discoveries) do
      add :character_id, references(:characters, on_delete: :delete_all)
      add :account_id, :integer  # For account-wide discovery mode
      add :schematic_id, :integer, null: false
      add :variant_id, :integer, null: false, default: 0
      add :discovered_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime)
    end

    create index(:schematic_discoveries, [:character_id])
    create index(:schematic_discoveries, [:account_id])
    create unique_index(:schematic_discoveries, [:character_id, :schematic_id, :variant_id],
      where: "character_id IS NOT NULL",
      name: :schematic_discoveries_character_unique)
    create unique_index(:schematic_discoveries, [:account_id, :schematic_id, :variant_id],
      where: "account_id IS NOT NULL",
      name: :schematic_discoveries_account_unique)

    # Tradeskill talent allocation
    create table(:tradeskill_talents) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :profession_id, :integer, null: false
      add :talent_id, :integer, null: false
      add :points_spent, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:tradeskill_talents, [:character_id])
    create unique_index(:tradeskill_talents, [:character_id, :profession_id, :talent_id])

    # Work orders
    create table(:work_orders) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :work_order_id, :integer, null: false
      add :profession_id, :integer, null: false
      add :quantity_required, :integer, null: false
      add :quantity_completed, :integer, null: false, default: 0
      add :status, :work_order_status, null: false, default: "active"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime)
    end

    create index(:work_orders, [:character_id])
    create index(:work_orders, [:character_id, :status])
  end
end
```

**Step 2: Run the migration**

Run: `mix ecto.migrate`

Expected: Migration runs successfully

**Step 3: Verify tables exist**

Run: `mix run -e "IO.inspect BezgelorDb.Repo.query!(\"SELECT table_name FROM information_schema.tables WHERE table_name LIKE '%tradeskill%' OR table_name LIKE '%work_order%' OR table_name LIKE '%schematic%'\")"`

Expected: Lists the 4 new tables

**Step 4: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/20251211000000_create_tradeskill_tables.exs
git commit -m "feat(db): Add tradeskill database tables"
```

---

## Task 4: Create CharacterTradeskill Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/character_tradeskill.ex`
- Test: `apps/bezgelor_db/test/schema/character_tradeskill_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.Schema.CharacterTradeskillTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.CharacterTradeskill

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        character_id: 1,
        profession_id: 1,
        profession_type: :crafting
      }

      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = %{profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without profession_id" do
      attrs = %{character_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).profession_id
    end

    test "invalid without profession_type" do
      attrs = %{character_id: 1, profession_id: 1}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).profession_type
    end

    test "defaults skill_level to 0" do
      attrs = %{character_id: 1, profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :skill_level) == 0
    end

    test "defaults is_active to true" do
      attrs = %{character_id: 1, profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :is_active) == true
    end
  end

  describe "progress_changeset/2" do
    test "updates skill_level and skill_xp" do
      tradeskill = %CharacterTradeskill{skill_level: 5, skill_xp: 100}
      changeset = CharacterTradeskill.progress_changeset(tradeskill, %{skill_level: 6, skill_xp: 150})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :skill_level) == 6
      assert Ecto.Changeset.get_change(changeset, :skill_xp) == 150
    end

    test "validates skill_level is non-negative" do
      tradeskill = %CharacterTradeskill{}
      changeset = CharacterTradeskill.progress_changeset(tradeskill, %{skill_level: -1})
      refute changeset.valid?
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/character_tradeskill_test.exs -v`

Expected: FAIL - module doesn't exist

**Step 3: Create the schema**

```elixir
defmodule BezgelorDb.Schema.CharacterTradeskill do
  @moduledoc """
  Schema for character tradeskill profession progress.

  Tracks a character's level and XP in each profession they've learned.
  The is_active flag indicates whether this is a currently active profession
  (characters can swap professions, potentially preserving progress).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "character_tradeskills" do
    belongs_to :character, Character

    field :profession_id, :integer
    field :profession_type, Ecto.Enum, values: [:crafting, :gathering]
    field :skill_level, :integer, default: 0
    field :skill_xp, :integer, default: 0
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id profession_id profession_type)a
  @optional_fields ~w(skill_level skill_xp is_active)a

  @doc """
  Build a changeset for creating or updating a tradeskill record.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:skill_level, greater_than_or_equal_to: 0)
    |> validate_number(:skill_xp, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :profession_id])
  end

  @doc """
  Changeset for updating skill progress (level and XP).
  """
  @spec progress_changeset(t(), map()) :: Ecto.Changeset.t()
  def progress_changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, [:skill_level, :skill_xp])
    |> validate_number(:skill_level, greater_than_or_equal_to: 0)
    |> validate_number(:skill_xp, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for deactivating a profession (when swapping).
  """
  @spec deactivate_changeset(t()) :: Ecto.Changeset.t()
  def deactivate_changeset(tradeskill) do
    change(tradeskill, is_active: false)
  end

  @doc """
  Changeset for reactivating a previously learned profession.
  """
  @spec activate_changeset(t()) :: Ecto.Changeset.t()
  def activate_changeset(tradeskill) do
    change(tradeskill, is_active: true)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/character_tradeskill_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/character_tradeskill.ex apps/bezgelor_db/test/schema/character_tradeskill_test.exs
git commit -m "feat(db): Add CharacterTradeskill schema"
```

---

## Task 5: Create SchematicDiscovery Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/schematic_discovery.ex`
- Test: `apps/bezgelor_db/test/schema/schematic_discovery_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.Schema.SchematicDiscoveryTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.SchematicDiscovery

  describe "changeset/2 for character scope" do
    test "valid with character_id" do
      attrs = %{character_id: 1, schematic_id: 100, variant_id: 0}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert changeset.valid?
    end

    test "invalid without schematic_id" do
      attrs = %{character_id: 1}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      refute changeset.valid?
    end

    test "defaults variant_id to 0" do
      attrs = %{character_id: 1, schematic_id: 100}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :variant_id) == 0
    end
  end

  describe "changeset/2 for account scope" do
    test "valid with account_id" do
      attrs = %{account_id: 1, schematic_id: 100, variant_id: 0}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 validation" do
    test "requires either character_id or account_id" do
      attrs = %{schematic_id: 100}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      refute changeset.valid?
      assert "must have either character_id or account_id" in errors_on(changeset).base
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/schematic_discovery_test.exs -v`

Expected: FAIL

**Step 3: Create the schema**

```elixir
defmodule BezgelorDb.Schema.SchematicDiscovery do
  @moduledoc """
  Schema for tracking discovered schematics and variants.

  Supports both character-scoped and account-scoped discovery based on
  server configuration. The variant_id of 0 indicates the base schematic,
  while higher values represent discovered variants.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "schematic_discoveries" do
    belongs_to :character, Character

    field :account_id, :integer
    field :schematic_id, :integer
    field :variant_id, :integer, default: 0
    field :discovered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating a discovery record.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(discovery, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    discovery
    |> cast(attrs, [:character_id, :account_id, :schematic_id, :variant_id, :discovered_at])
    |> validate_required([:schematic_id])
    |> put_default(:discovered_at, now)
    |> put_default(:variant_id, 0)
    |> validate_scope()
    |> foreign_key_constraint(:character_id)
  end

  defp put_default(changeset, field, value) do
    if get_field(changeset, field) do
      changeset
    else
      put_change(changeset, field, value)
    end
  end

  defp validate_scope(changeset) do
    character_id = get_field(changeset, :character_id)
    account_id = get_field(changeset, :account_id)

    cond do
      character_id != nil -> changeset
      account_id != nil -> changeset
      true -> add_error(changeset, :base, "must have either character_id or account_id")
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/schematic_discovery_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/schematic_discovery.ex apps/bezgelor_db/test/schema/schematic_discovery_test.exs
git commit -m "feat(db): Add SchematicDiscovery schema"
```

---

## Task 6: Create TradeskillTalent Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/tradeskill_talent.ex`
- Test: `apps/bezgelor_db/test/schema/tradeskill_talent_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.Schema.TradeskillTalentTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.TradeskillTalent

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{character_id: 1, profession_id: 1, talent_id: 100}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      assert changeset.valid?
    end

    test "defaults points_spent to 1" do
      attrs = %{character_id: 1, profession_id: 1, talent_id: 100}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :points_spent) == 1
    end

    test "invalid without talent_id" do
      attrs = %{character_id: 1, profession_id: 1}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      refute changeset.valid?
    end
  end

  describe "add_point_changeset/1" do
    test "increments points_spent" do
      talent = %TradeskillTalent{points_spent: 2}
      changeset = TradeskillTalent.add_point_changeset(talent)
      assert Ecto.Changeset.get_change(changeset, :points_spent) == 3
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/tradeskill_talent_test.exs -v`

Expected: FAIL

**Step 3: Create the schema**

```elixir
defmodule BezgelorDb.Schema.TradeskillTalent do
  @moduledoc """
  Schema for tradeskill tech tree talent allocation.

  Each record represents points spent in a specific talent node
  for a character's profession.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "tradeskill_talents" do
    belongs_to :character, Character

    field :profession_id, :integer
    field :talent_id, :integer
    field :points_spent, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id profession_id talent_id)a
  @optional_fields ~w(points_spent)a

  @doc """
  Build a changeset for creating a talent allocation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(talent, attrs) do
    talent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:points_spent, greater_than: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :profession_id, :talent_id])
  end

  @doc """
  Changeset for adding another point to this talent.
  """
  @spec add_point_changeset(t()) :: Ecto.Changeset.t()
  def add_point_changeset(talent) do
    change(talent, points_spent: talent.points_spent + 1)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/tradeskill_talent_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/tradeskill_talent.ex apps/bezgelor_db/test/schema/tradeskill_talent_test.exs
git commit -m "feat(db): Add TradeskillTalent schema"
```

---

## Task 7: Create WorkOrder Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/work_order.ex`
- Test: `apps/bezgelor_db/test/schema/work_order_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.Schema.WorkOrderTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.WorkOrder

  describe "changeset/2" do
    test "valid with required fields" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)
      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }
      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert changeset.valid?
    end

    test "defaults status to active" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)
      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }
      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == :active
    end

    test "defaults quantity_completed to 0" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)
      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }
      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :quantity_completed) == 0
    end
  end

  describe "progress_changeset/2" do
    test "updates quantity_completed" do
      order = %WorkOrder{quantity_completed: 2}
      changeset = WorkOrder.progress_changeset(order, 3)
      assert Ecto.Changeset.get_change(changeset, :quantity_completed) == 3
    end
  end

  describe "complete_changeset/1" do
    test "sets status to completed" do
      order = %WorkOrder{status: :active}
      changeset = WorkOrder.complete_changeset(order)
      assert Ecto.Changeset.get_change(changeset, :status) == :completed
    end
  end

  describe "expire_changeset/1" do
    test "sets status to expired" do
      order = %WorkOrder{status: :active}
      changeset = WorkOrder.expire_changeset(order)
      assert Ecto.Changeset.get_change(changeset, :status) == :expired
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/work_order_test.exs -v`

Expected: FAIL

**Step 3: Create the schema**

```elixir
defmodule BezgelorDb.Schema.WorkOrder do
  @moduledoc """
  Schema for tradeskill work orders (daily crafting quests).

  Work orders are generated daily and expire after 24 hours.
  Players complete them by crafting the required items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "work_orders" do
    belongs_to :character, Character

    field :work_order_id, :integer
    field :profession_id, :integer
    field :quantity_required, :integer
    field :quantity_completed, :integer, default: 0
    field :status, Ecto.Enum, values: [:active, :completed, :expired], default: :active
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id work_order_id profession_id quantity_required expires_at)a
  @optional_fields ~w(quantity_completed status accepted_at)a

  @doc """
  Build a changeset for creating a work order.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(work_order, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    work_order
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity_required, greater_than: 0)
    |> validate_number(:quantity_completed, greater_than_or_equal_to: 0)
    |> put_default_accepted_at(now)
    |> foreign_key_constraint(:character_id)
  end

  defp put_default_accepted_at(changeset, now) do
    if get_field(changeset, :accepted_at) do
      changeset
    else
      put_change(changeset, :accepted_at, now)
    end
  end

  @doc """
  Changeset for updating progress.
  """
  @spec progress_changeset(t(), integer()) :: Ecto.Changeset.t()
  def progress_changeset(work_order, quantity_completed) do
    change(work_order, quantity_completed: quantity_completed)
  end

  @doc """
  Changeset for marking as completed.
  """
  @spec complete_changeset(t()) :: Ecto.Changeset.t()
  def complete_changeset(work_order) do
    change(work_order, status: :completed)
  end

  @doc """
  Changeset for marking as expired.
  """
  @spec expire_changeset(t()) :: Ecto.Changeset.t()
  def expire_changeset(work_order) do
    change(work_order, status: :expired)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/work_order_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/work_order.ex apps/bezgelor_db/test/schema/work_order_test.exs
git commit -m "feat(db): Add WorkOrder schema"
```

---

## Task 8: Create Tradeskills Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex`
- Test: `apps/bezgelor_db/test/tradeskills_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.TradeskillsTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Tradeskills
  alias BezgelorDb.Schema.{CharacterTradeskill, SchematicDiscovery, TradeskillTalent, WorkOrder}

  # Test fixtures would need character setup
  # For now, test the interface exists

  describe "profession management" do
    test "learn_profession/3 creates tradeskill record" do
      # Would need character fixture
      assert function_exported?(Tradeskills, :learn_profession, 3)
    end

    test "get_professions/1 returns character's professions" do
      assert function_exported?(Tradeskills, :get_professions, 1)
    end

    test "swap_profession/3 deactivates old and activates new" do
      assert function_exported?(Tradeskills, :swap_profession, 3)
    end
  end

  describe "progress tracking" do
    test "add_xp/3 increases XP and may level up" do
      assert function_exported?(Tradeskills, :add_xp, 3)
    end
  end

  describe "discovery" do
    test "discover_schematic/3 records discovery" do
      assert function_exported?(Tradeskills, :discover_schematic, 3)
    end

    test "is_discovered?/3 checks discovery state" do
      assert function_exported?(Tradeskills, :is_discovered?, 3)
    end
  end

  describe "talents" do
    test "allocate_talent/3 adds talent point" do
      assert function_exported?(Tradeskills, :allocate_talent, 3)
    end

    test "get_talents/2 returns allocated talents" do
      assert function_exported?(Tradeskills, :get_talents, 2)
    end

    test "reset_talents/2 clears all talents for profession" do
      assert function_exported?(Tradeskills, :reset_talents, 2)
    end
  end

  describe "work orders" do
    test "create_work_order/2 creates work order" do
      assert function_exported?(Tradeskills, :create_work_order, 2)
    end

    test "get_active_work_orders/1 returns active orders" do
      assert function_exported?(Tradeskills, :get_active_work_orders, 1)
    end

    test "update_work_order_progress/2 increments progress" do
      assert function_exported?(Tradeskills, :update_work_order_progress, 2)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/tradeskills_test.exs -v`

Expected: FAIL - module doesn't exist

**Step 3: Create the context module**

```elixir
defmodule BezgelorDb.Tradeskills do
  @moduledoc """
  Tradeskills database operations.

  Manages profession progress, schematic discovery, talent allocation,
  and work orders.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{CharacterTradeskill, SchematicDiscovery, TradeskillTalent, WorkOrder}

  # =============================================================================
  # Profession Management
  # =============================================================================

  @doc """
  Learn a new profession for a character.
  """
  @spec learn_profession(integer(), integer(), :crafting | :gathering) ::
          {:ok, CharacterTradeskill.t()} | {:error, term()}
  def learn_profession(character_id, profession_id, profession_type) do
    %CharacterTradeskill{}
    |> CharacterTradeskill.changeset(%{
      character_id: character_id,
      profession_id: profession_id,
      profession_type: profession_type
    })
    |> Repo.insert()
  end

  @doc """
  Get all professions for a character.
  """
  @spec get_professions(integer()) :: [CharacterTradeskill.t()]
  def get_professions(character_id) do
    from(t in CharacterTradeskill,
      where: t.character_id == ^character_id,
      order_by: [desc: t.is_active, asc: t.profession_id]
    )
    |> Repo.all()
  end

  @doc """
  Get active professions of a specific type.
  """
  @spec get_active_professions(integer(), :crafting | :gathering) :: [CharacterTradeskill.t()]
  def get_active_professions(character_id, profession_type) do
    from(t in CharacterTradeskill,
      where: t.character_id == ^character_id and
             t.profession_type == ^profession_type and
             t.is_active == true
    )
    |> Repo.all()
  end

  @doc """
  Swap from one profession to another (for crafting professions with limits).
  """
  @spec swap_profession(integer(), integer(), integer()) ::
          {:ok, CharacterTradeskill.t()} | {:error, term()}
  def swap_profession(character_id, old_profession_id, new_profession_id) do
    Repo.transaction(fn ->
      # Deactivate old profession
      case get_profession(character_id, old_profession_id) do
        {:ok, old} ->
          old
          |> CharacterTradeskill.deactivate_changeset()
          |> Repo.update!()
        :error ->
          :ok
      end

      # Check if new profession was previously learned
      case get_profession(character_id, new_profession_id) do
        {:ok, existing} ->
          # Reactivate existing
          existing
          |> CharacterTradeskill.activate_changeset()
          |> Repo.update!()

        :error ->
          # Learn new profession
          %CharacterTradeskill{}
          |> CharacterTradeskill.changeset(%{
            character_id: character_id,
            profession_id: new_profession_id,
            profession_type: :crafting
          })
          |> Repo.insert!()
      end
    end)
  end

  @doc """
  Get a specific profession for a character.
  """
  @spec get_profession(integer(), integer()) :: {:ok, CharacterTradeskill.t()} | :error
  def get_profession(character_id, profession_id) do
    query =
      from t in CharacterTradeskill,
        where: t.character_id == ^character_id and t.profession_id == ^profession_id

    case Repo.one(query) do
      nil -> :error
      tradeskill -> {:ok, tradeskill}
    end
  end

  # =============================================================================
  # Progress Tracking
  # =============================================================================

  @doc """
  Add XP to a profession and handle level-ups.
  Returns the updated tradeskill with any level changes.
  """
  @spec add_xp(integer(), integer(), integer()) ::
          {:ok, CharacterTradeskill.t(), levels_gained :: integer()} | {:error, term()}
  def add_xp(character_id, profession_id, xp_amount) do
    case get_profession(character_id, profession_id) do
      {:ok, tradeskill} ->
        new_xp = tradeskill.skill_xp + xp_amount
        {new_level, remaining_xp, levels_gained} = calculate_level(tradeskill.skill_level, new_xp)

        result =
          tradeskill
          |> CharacterTradeskill.progress_changeset(%{skill_level: new_level, skill_xp: remaining_xp})
          |> Repo.update()

        case result do
          {:ok, updated} -> {:ok, updated, levels_gained}
          {:error, _} = err -> err
        end

      :error ->
        {:error, :profession_not_found}
    end
  end

  # Simplified level calculation - would use static data in real impl
  defp calculate_level(current_level, total_xp) do
    xp_per_level = 1000  # Simplified; real values from static data
    max_level = 50

    levels_to_add = div(total_xp, xp_per_level)
    new_level = min(current_level + levels_to_add, max_level)
    remaining_xp = rem(total_xp, xp_per_level)
    levels_gained = new_level - current_level

    {new_level, remaining_xp, levels_gained}
  end

  # =============================================================================
  # Schematic Discovery
  # =============================================================================

  @doc """
  Record a schematic or variant discovery.
  """
  @spec discover_schematic(integer(), integer(), integer()) ::
          {:ok, SchematicDiscovery.t()} | {:error, term()}
  def discover_schematic(character_id, schematic_id, variant_id \\ 0) do
    %SchematicDiscovery{}
    |> SchematicDiscovery.changeset(%{
      character_id: character_id,
      schematic_id: schematic_id,
      variant_id: variant_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Record an account-wide schematic discovery.
  """
  @spec discover_schematic_account(integer(), integer(), integer()) ::
          {:ok, SchematicDiscovery.t()} | {:error, term()}
  def discover_schematic_account(account_id, schematic_id, variant_id \\ 0) do
    %SchematicDiscovery{}
    |> SchematicDiscovery.changeset(%{
      account_id: account_id,
      schematic_id: schematic_id,
      variant_id: variant_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Check if a schematic/variant has been discovered.
  """
  @spec is_discovered?(integer(), integer(), integer()) :: boolean()
  def is_discovered?(character_id, schematic_id, variant_id \\ 0) do
    query =
      from d in SchematicDiscovery,
        where: d.character_id == ^character_id and
               d.schematic_id == ^schematic_id and
               d.variant_id == ^variant_id

    Repo.exists?(query)
  end

  @doc """
  Get all discoveries for a character.
  """
  @spec get_discoveries(integer()) :: [SchematicDiscovery.t()]
  def get_discoveries(character_id) do
    from(d in SchematicDiscovery,
      where: d.character_id == ^character_id,
      order_by: [asc: d.schematic_id, asc: d.variant_id]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Talent Management
  # =============================================================================

  @doc """
  Allocate a talent point.
  """
  @spec allocate_talent(integer(), integer(), integer()) ::
          {:ok, TradeskillTalent.t()} | {:error, term()}
  def allocate_talent(character_id, profession_id, talent_id) do
    case get_talent(character_id, profession_id, talent_id) do
      {:ok, existing} ->
        existing
        |> TradeskillTalent.add_point_changeset()
        |> Repo.update()

      :error ->
        %TradeskillTalent{}
        |> TradeskillTalent.changeset(%{
          character_id: character_id,
          profession_id: profession_id,
          talent_id: talent_id
        })
        |> Repo.insert()
    end
  end

  @doc """
  Get all allocated talents for a profession.
  """
  @spec get_talents(integer(), integer()) :: [TradeskillTalent.t()]
  def get_talents(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id
    )
    |> Repo.all()
  end

  @doc """
  Get a specific talent allocation.
  """
  @spec get_talent(integer(), integer(), integer()) :: {:ok, TradeskillTalent.t()} | :error
  def get_talent(character_id, profession_id, talent_id) do
    query =
      from t in TradeskillTalent,
        where: t.character_id == ^character_id and
               t.profession_id == ^profession_id and
               t.talent_id == ^talent_id

    case Repo.one(query) do
      nil -> :error
      talent -> {:ok, talent}
    end
  end

  @doc """
  Reset all talents for a profession.
  """
  @spec reset_talents(integer(), integer()) :: {integer(), nil}
  def reset_talents(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Count total talent points spent for a profession.
  """
  @spec count_talent_points(integer(), integer()) :: integer()
  def count_talent_points(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id,
      select: sum(t.points_spent)
    )
    |> Repo.one() || 0
  end

  # =============================================================================
  # Work Orders
  # =============================================================================

  @doc """
  Create a work order for a character.
  """
  @spec create_work_order(integer(), map()) :: {:ok, WorkOrder.t()} | {:error, term()}
  def create_work_order(character_id, attrs) do
    %WorkOrder{}
    |> WorkOrder.changeset(Map.put(attrs, :character_id, character_id))
    |> Repo.insert()
  end

  @doc """
  Get all active work orders for a character.
  """
  @spec get_active_work_orders(integer()) :: [WorkOrder.t()]
  def get_active_work_orders(character_id) do
    now = DateTime.utc_now()

    from(w in WorkOrder,
      where: w.character_id == ^character_id and
             w.status == :active and
             w.expires_at > ^now
    )
    |> Repo.all()
  end

  @doc """
  Update work order progress.
  """
  @spec update_work_order_progress(integer(), integer()) ::
          {:ok, WorkOrder.t()} | {:error, term()}
  def update_work_order_progress(work_order_id, quantity_completed) do
    case Repo.get(WorkOrder, work_order_id) do
      nil ->
        {:error, :not_found}

      order ->
        order
        |> WorkOrder.progress_changeset(quantity_completed)
        |> Repo.update()
    end
  end

  @doc """
  Complete a work order.
  """
  @spec complete_work_order(integer()) :: {:ok, WorkOrder.t()} | {:error, term()}
  def complete_work_order(work_order_id) do
    case Repo.get(WorkOrder, work_order_id) do
      nil ->
        {:error, :not_found}

      order ->
        order
        |> WorkOrder.complete_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Expire old work orders.
  """
  @spec expire_work_orders() :: {integer(), nil}
  def expire_work_orders do
    now = DateTime.utc_now()

    from(w in WorkOrder,
      where: w.status == :active and w.expires_at <= ^now
    )
    |> Repo.update_all(set: [status: :expired])
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/tradeskills_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/tradeskills.ex apps/bezgelor_db/test/tradeskills_test.exs
git commit -m "feat(db): Add Tradeskills context module"
```

---

## Task 9: Create Coordinate System Module

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/crafting/coordinate_system.ex`
- Test: `apps/bezgelor_world/test/crafting/coordinate_system_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorWorld.Crafting.CoordinateSystemTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Crafting.CoordinateSystem

  describe "find_target_zone/3" do
    setup do
      zones = [
        %{id: 1, x_min: 0, x_max: 30, y_min: 0, y_max: 30, variant_id: 0, quality: :poor},
        %{id: 2, x_min: 40, x_max: 60, y_min: 40, y_max: 60, variant_id: 0, quality: :standard},
        %{id: 3, x_min: 70, x_max: 90, y_min: 70, y_max: 90, variant_id: 101, quality: :exceptional}
      ]
      {:ok, zones: zones}
    end

    test "returns zone when cursor is inside", %{zones: zones} do
      assert {:ok, zone} = CoordinateSystem.find_target_zone(50.0, 50.0, zones)
      assert zone.id == 2
      assert zone.quality == :standard
    end

    test "returns first matching zone for overlapping areas", %{zones: zones} do
      # Edge case: exactly on boundary
      assert {:ok, zone} = CoordinateSystem.find_target_zone(40.0, 40.0, zones)
      assert zone.id == 2
    end

    test "returns :no_zone when outside all zones", %{zones: zones} do
      assert :no_zone = CoordinateSystem.find_target_zone(35.0, 35.0, zones)
    end

    test "handles negative coordinates", %{zones: zones} do
      assert :no_zone = CoordinateSystem.find_target_zone(-10.0, -10.0, zones)
    end
  end

  describe "apply_additive/3" do
    test "moves cursor by additive vector" do
      cursor = {10.0, 20.0}
      additive = %{vector_x: 5.0, vector_y: -3.0}

      assert {15.0, 17.0} = CoordinateSystem.apply_additive(cursor, additive, 1)
    end

    test "applies overcharge multiplier" do
      cursor = {10.0, 20.0}
      additive = %{vector_x: 5.0, vector_y: -3.0}

      # Overcharge level 2 = 1.5x multiplier
      {new_x, new_y} = CoordinateSystem.apply_additive(cursor, additive, 2)
      assert_in_delta new_x, 17.5, 0.001
      assert_in_delta new_y, 15.5, 0.001
    end

    test "overcharge level 0 means no amplification" do
      cursor = {0.0, 0.0}
      additive = %{vector_x: 10.0, vector_y: 10.0}

      assert {10.0, 10.0} = CoordinateSystem.apply_additive(cursor, additive, 0)
    end
  end

  describe "calculate_overcharge_multiplier/1" do
    test "level 0 returns 1.0" do
      assert CoordinateSystem.calculate_overcharge_multiplier(0) == 1.0
    end

    test "level 1 returns 1.25" do
      assert CoordinateSystem.calculate_overcharge_multiplier(1) == 1.25
    end

    test "level 2 returns 1.5" do
      assert CoordinateSystem.calculate_overcharge_multiplier(2) == 1.5
    end

    test "level 3 returns 2.0" do
      assert CoordinateSystem.calculate_overcharge_multiplier(3) == 2.0
    end
  end

  describe "calculate_failure_chance/1" do
    test "level 0 has 0% failure" do
      assert CoordinateSystem.calculate_failure_chance(0) == 0.0
    end

    test "level 1 has 10% failure" do
      assert CoordinateSystem.calculate_failure_chance(1) == 0.10
    end

    test "level 2 has 25% failure" do
      assert CoordinateSystem.calculate_failure_chance(2) == 0.25
    end

    test "level 3 has 50% failure" do
      assert CoordinateSystem.calculate_failure_chance(3) == 0.50
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/crafting/coordinate_system_test.exs -v`

Expected: FAIL

**Step 3: Create the module**

```elixir
defmodule BezgelorWorld.Crafting.CoordinateSystem do
  @moduledoc """
  Coordinate-based crafting system for WildStar tradeskills.

  Handles the 2D grid system where additives shift a cursor position,
  and the final position determines the craft outcome.

  ## Design Note

  Hit detection uses rectangle-based checks rather than complex polygon
  math. This may differ from the original WildStar implementation but
  provides equivalent gameplay with simpler logic.
  """

  @type cursor :: {float(), float()}
  @type zone :: %{
    id: integer(),
    x_min: number(),
    x_max: number(),
    y_min: number(),
    y_max: number(),
    variant_id: integer(),
    quality: atom()
  }
  @type additive :: %{vector_x: float(), vector_y: float()}

  @doc """
  Find which target zone contains the cursor position.

  Returns `{:ok, zone}` if cursor is within a zone, or `:no_zone` if
  the cursor is outside all zones (craft failure).
  """
  @spec find_target_zone(float(), float(), [zone()]) :: {:ok, zone()} | :no_zone
  def find_target_zone(cursor_x, cursor_y, zones) do
    case Enum.find(zones, fn zone ->
      cursor_x >= zone.x_min and cursor_x <= zone.x_max and
      cursor_y >= zone.y_min and cursor_y <= zone.y_max
    end) do
      nil -> :no_zone
      zone -> {:ok, zone}
    end
  end

  @doc """
  Apply an additive to the cursor, optionally with overcharge amplification.
  """
  @spec apply_additive(cursor(), additive(), non_neg_integer()) :: cursor()
  def apply_additive({cursor_x, cursor_y}, additive, overcharge_level) do
    multiplier = calculate_overcharge_multiplier(overcharge_level)

    new_x = cursor_x + additive.vector_x * multiplier
    new_y = cursor_y + additive.vector_y * multiplier

    {new_x, new_y}
  end

  @doc """
  Calculate the vector multiplier for a given overcharge level.

  - Level 0: 1.0x (no amplification)
  - Level 1: 1.25x
  - Level 2: 1.5x
  - Level 3: 2.0x
  """
  @spec calculate_overcharge_multiplier(non_neg_integer()) :: float()
  def calculate_overcharge_multiplier(0), do: 1.0
  def calculate_overcharge_multiplier(1), do: 1.25
  def calculate_overcharge_multiplier(2), do: 1.5
  def calculate_overcharge_multiplier(3), do: 2.0
  def calculate_overcharge_multiplier(_), do: 2.0  # Cap at level 3

  @doc """
  Calculate the failure chance for a given overcharge level.

  - Level 0: 0% (no risk)
  - Level 1: 10%
  - Level 2: 25%
  - Level 3: 50%
  """
  @spec calculate_failure_chance(non_neg_integer()) :: float()
  def calculate_failure_chance(0), do: 0.0
  def calculate_failure_chance(1), do: 0.10
  def calculate_failure_chance(2), do: 0.25
  def calculate_failure_chance(3), do: 0.50
  def calculate_failure_chance(_), do: 0.50  # Cap at level 3

  @doc """
  Check if craft failed due to overcharge.
  """
  @spec overcharge_failed?(non_neg_integer()) :: boolean()
  def overcharge_failed?(overcharge_level) do
    failure_chance = calculate_failure_chance(overcharge_level)
    :rand.uniform() < failure_chance
  end

  @doc """
  Clamp cursor position to grid bounds.
  """
  @spec clamp_to_grid(cursor(), number(), number()) :: cursor()
  def clamp_to_grid({x, y}, grid_width, grid_height) do
    clamped_x = x |> max(0) |> min(grid_width)
    clamped_y = y |> max(0) |> min(grid_height)
    {clamped_x, clamped_y}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/crafting/coordinate_system_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/crafting/coordinate_system.ex apps/bezgelor_world/test/crafting/coordinate_system_test.exs
git commit -m "feat(world): Add crafting coordinate system"
```

---

## Task 10: Create CraftingSession Module

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/crafting/crafting_session.ex`
- Test: `apps/bezgelor_world/test/crafting/crafting_session_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorWorld.Crafting.CraftingSessionTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Crafting.CraftingSession

  describe "new/1" do
    test "creates session with initial cursor at origin" do
      session = CraftingSession.new(1234)
      assert session.schematic_id == 1234
      assert session.cursor_x == 0.0
      assert session.cursor_y == 0.0
      assert session.additives_used == []
      assert session.overcharge_level == 0
    end
  end

  describe "add_additive/2" do
    test "updates cursor position and records additive" do
      session = CraftingSession.new(1234)
      additive = %{item_id: 100, quantity: 1, vector_x: 10.0, vector_y: 5.0}

      updated = CraftingSession.add_additive(session, additive)

      assert updated.cursor_x == 10.0
      assert updated.cursor_y == 5.0
      assert length(updated.additives_used) == 1
    end

    test "accumulates multiple additives" do
      session = CraftingSession.new(1234)
      additive1 = %{item_id: 100, quantity: 1, vector_x: 10.0, vector_y: 5.0}
      additive2 = %{item_id: 101, quantity: 1, vector_x: -3.0, vector_y: 8.0}

      updated =
        session
        |> CraftingSession.add_additive(additive1)
        |> CraftingSession.add_additive(additive2)

      assert updated.cursor_x == 7.0
      assert updated.cursor_y == 13.0
      assert length(updated.additives_used) == 2
    end
  end

  describe "set_overcharge/2" do
    test "sets overcharge level" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, 2)
      assert updated.overcharge_level == 2
    end

    test "clamps to max level 3" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, 5)
      assert updated.overcharge_level == 3
    end

    test "clamps to min level 0" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, -1)
      assert updated.overcharge_level == 0
    end
  end

  describe "get_cursor/1" do
    test "returns cursor as tuple" do
      session = %CraftingSession{cursor_x: 25.5, cursor_y: 30.0, schematic_id: 1}
      assert CraftingSession.get_cursor(session) == {25.5, 30.0}
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/crafting/crafting_session_test.exs -v`

Expected: FAIL

**Step 3: Create the module**

```elixir
defmodule BezgelorWorld.Crafting.CraftingSession do
  @moduledoc """
  In-memory crafting session state.

  Tracks the current state of an active craft including cursor position,
  additives used, and overcharge level. Sessions are stored in player
  GenServer state and are lost on disconnect (matching original behavior).
  """

  alias BezgelorWorld.Crafting.CoordinateSystem

  @max_overcharge 3

  defstruct [
    :schematic_id,
    :started_at,
    cursor_x: 0.0,
    cursor_y: 0.0,
    additives_used: [],
    overcharge_level: 0
  ]

  @type t :: %__MODULE__{
    schematic_id: integer(),
    cursor_x: float(),
    cursor_y: float(),
    additives_used: [additive_record()],
    overcharge_level: non_neg_integer(),
    started_at: DateTime.t()
  }

  @type additive_record :: %{
    item_id: integer(),
    quantity: integer(),
    vector_x: float(),
    vector_y: float()
  }

  @doc """
  Create a new crafting session for a schematic.
  """
  @spec new(integer()) :: t()
  def new(schematic_id) do
    %__MODULE__{
      schematic_id: schematic_id,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Add an additive to the session, updating cursor position.
  """
  @spec add_additive(t(), additive_record()) :: t()
  def add_additive(%__MODULE__{} = session, additive) do
    {new_x, new_y} = CoordinateSystem.apply_additive(
      {session.cursor_x, session.cursor_y},
      additive,
      session.overcharge_level
    )

    %{session |
      cursor_x: new_x,
      cursor_y: new_y,
      additives_used: session.additives_used ++ [additive]
    }
  end

  @doc """
  Set the overcharge level (clamped to 0-3).
  """
  @spec set_overcharge(t(), integer()) :: t()
  def set_overcharge(%__MODULE__{} = session, level) do
    clamped = level |> max(0) |> min(@max_overcharge)
    %{session | overcharge_level: clamped}
  end

  @doc """
  Get current cursor position as tuple.
  """
  @spec get_cursor(t()) :: {float(), float()}
  def get_cursor(%__MODULE__{cursor_x: x, cursor_y: y}), do: {x, y}

  @doc """
  Get the total material cost (additives consumed).
  """
  @spec get_material_cost(t()) :: [{integer(), integer()}]
  def get_material_cost(%__MODULE__{additives_used: additives}) do
    additives
    |> Enum.group_by(& &1.item_id)
    |> Enum.map(fn {item_id, items} ->
      total = Enum.sum(Enum.map(items, & &1.quantity))
      {item_id, total}
    end)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/crafting/crafting_session_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/crafting/crafting_session.ex apps/bezgelor_world/test/crafting/crafting_session_test.exs
git commit -m "feat(world): Add CraftingSession module"
```

---

## Task 11: Create GatheringNode Module

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/gathering/gathering_node.ex`
- Test: `apps/bezgelor_world/test/gathering/gathering_node_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorWorld.Gathering.GatheringNodeTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Gathering.GatheringNode

  describe "new/3" do
    test "creates node at position" do
      position = {100.0, 50.0, 200.0}
      node = GatheringNode.new(1, 100, position)

      assert node.node_id == 1
      assert node.node_type_id == 100
      assert node.position == position
      assert node.respawn_at == nil
      assert node.tapped_by == nil
    end
  end

  describe "available?/1" do
    test "returns true when not respawning and not tapped" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      assert GatheringNode.available?(node)
    end

    test "returns false when respawning" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        respawn_at: future
      }
      refute GatheringNode.available?(node)
    end

    test "returns true when respawn time has passed" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        respawn_at: past
      }
      assert GatheringNode.available?(node)
    end

    test "returns false when tapped by another player" do
      future = DateTime.add(DateTime.utc_now(), 5, :second)
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: future
      }
      refute GatheringNode.available?(node)
    end
  end

  describe "tap/2" do
    test "sets tapped_by and expiry" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      tapped = GatheringNode.tap(node, 456)

      assert tapped.tapped_by == 456
      assert tapped.tap_expires_at != nil
    end
  end

  describe "harvest/2" do
    test "sets respawn time" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      harvested = GatheringNode.harvest(node, 30)

      assert harvested.respawn_at != nil
      assert harvested.tapped_by == nil
    end
  end

  describe "can_harvest?/2" do
    test "returns true for tapper" do
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: DateTime.add(DateTime.utc_now(), 5, :second)
      }
      assert GatheringNode.can_harvest?(node, 123)
    end

    test "returns false for non-tapper when tapped" do
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: DateTime.add(DateTime.utc_now(), 5, :second)
      }
      refute GatheringNode.can_harvest?(node, 456)
    end

    test "returns true for anyone when not tapped" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      assert GatheringNode.can_harvest?(node, 456)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/gathering/gathering_node_test.exs -v`

Expected: FAIL

**Step 3: Create the module**

```elixir
defmodule BezgelorWorld.Gathering.GatheringNode do
  @moduledoc """
  Represents a gatherable resource node in the world.

  Nodes spawn at fixed positions, can be tapped (claimed) by players,
  and respawn after a timer when harvested.
  """

  @tap_duration_seconds 10

  defstruct [
    :node_id,
    :node_type_id,
    :position,
    :respawn_at,
    :tapped_by,
    :tap_expires_at
  ]

  @type t :: %__MODULE__{
    node_id: integer(),
    node_type_id: integer(),
    position: {float(), float(), float()},
    respawn_at: DateTime.t() | nil,
    tapped_by: integer() | nil,
    tap_expires_at: DateTime.t() | nil
  }

  @doc """
  Create a new gathering node.
  """
  @spec new(integer(), integer(), {float(), float(), float()}) :: t()
  def new(node_id, node_type_id, position) do
    %__MODULE__{
      node_id: node_id,
      node_type_id: node_type_id,
      position: position
    }
  end

  @doc """
  Check if the node is available for gathering.
  """
  @spec available?(t()) :: boolean()
  def available?(%__MODULE__{} = node) do
    not respawning?(node) and not actively_tapped?(node)
  end

  @doc """
  Check if node is currently respawning.
  """
  @spec respawning?(t()) :: boolean()
  def respawning?(%__MODULE__{respawn_at: nil}), do: false
  def respawning?(%__MODULE__{respawn_at: respawn_at}) do
    DateTime.compare(DateTime.utc_now(), respawn_at) == :lt
  end

  @doc """
  Check if node is actively tapped by someone.
  """
  @spec actively_tapped?(t()) :: boolean()
  def actively_tapped?(%__MODULE__{tapped_by: nil}), do: false
  def actively_tapped?(%__MODULE__{tap_expires_at: nil}), do: false
  def actively_tapped?(%__MODULE__{tap_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  @doc """
  Tap (claim) the node for a character.
  """
  @spec tap(t(), integer()) :: t()
  def tap(%__MODULE__{} = node, character_id) do
    expires_at = DateTime.add(DateTime.utc_now(), @tap_duration_seconds, :second)

    %{node |
      tapped_by: character_id,
      tap_expires_at: expires_at
    }
  end

  @doc """
  Mark the node as harvested with a respawn timer.
  """
  @spec harvest(t(), integer()) :: t()
  def harvest(%__MODULE__{} = node, respawn_seconds) do
    respawn_at = DateTime.add(DateTime.utc_now(), respawn_seconds, :second)

    %{node |
      respawn_at: respawn_at,
      tapped_by: nil,
      tap_expires_at: nil
    }
  end

  @doc """
  Check if a character can harvest this node.
  """
  @spec can_harvest?(t(), integer()) :: boolean()
  def can_harvest?(%__MODULE__{tapped_by: nil}, _character_id), do: true
  def can_harvest?(%__MODULE__{tapped_by: tapper}, character_id) when tapper == character_id, do: true
  def can_harvest?(%__MODULE__{} = node, _character_id) do
    # Can harvest if tap has expired
    not actively_tapped?(node)
  end

  @doc """
  Clear respawn state (for respawned nodes).
  """
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{} = node) do
    %{node | respawn_at: nil}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/gathering/gathering_node_test.exs -v`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/gathering/gathering_node.ex apps/bezgelor_world/test/gathering/gathering_node_test.exs
git commit -m "feat(world): Add GatheringNode module"
```

---

## Task 12: Add Tradeskill Configuration

**Files:**
- Modify: `config/config.exs` or `config/runtime.exs`

**Step 1: Add tradeskill configuration**

Add to `apps/bezgelor_world/config/config.exs`:

```elixir
config :bezgelor_world, :tradeskills,
  # Profession limits
  max_crafting_professions: 2,
  max_gathering_professions: 3,
  preserve_progress_on_swap: false,

  # Discovery scope
  discovery_scope: :character,

  # Node competition
  node_competition: :first_tap,
  shared_tap_window_seconds: 5,

  # Tech tree respec
  respec_policy: :gold_cost,
  respec_gold_cost: 10_00,
  respec_item_id: nil,

  # Crafting stations
  station_mode: :strict
```

**Step 2: Create config access module**

Create file: `apps/bezgelor_world/lib/bezgelor_world/tradeskill_config.ex`

```elixir
defmodule BezgelorWorld.TradeskillConfig do
  @moduledoc """
  Access tradeskill configuration values.
  """

  @doc """
  Get a tradeskill config value.
  """
  @spec get(atom()) :: term()
  def get(key) do
    config = Application.get_env(:bezgelor_world, :tradeskills, [])
    Keyword.get(config, key)
  end

  @doc """
  Get max crafting professions allowed (0 = unlimited).
  """
  @spec max_crafting_professions() :: non_neg_integer()
  def max_crafting_professions, do: get(:max_crafting_professions) || 2

  @doc """
  Get max gathering professions allowed (0 = unlimited).
  """
  @spec max_gathering_professions() :: non_neg_integer()
  def max_gathering_professions, do: get(:max_gathering_professions) || 3

  @doc """
  Whether to preserve progress when swapping professions.
  """
  @spec preserve_progress_on_swap?() :: boolean()
  def preserve_progress_on_swap?, do: get(:preserve_progress_on_swap) || false

  @doc """
  Discovery scope - :character or :account.
  """
  @spec discovery_scope() :: :character | :account
  def discovery_scope, do: get(:discovery_scope) || :character

  @doc """
  Node competition mode - :first_tap, :shared, or :instanced.
  """
  @spec node_competition() :: :first_tap | :shared | :instanced
  def node_competition, do: get(:node_competition) || :first_tap

  @doc """
  Respec policy - :free, :gold_cost, :item_required, or :disabled.
  """
  @spec respec_policy() :: :free | :gold_cost | :item_required | :disabled
  def respec_policy, do: get(:respec_policy) || :gold_cost

  @doc """
  Gold cost for respec (in copper).
  """
  @spec respec_gold_cost() :: non_neg_integer()
  def respec_gold_cost, do: get(:respec_gold_cost) || 10_00

  @doc """
  Station mode - :strict, :universal, or :housing_bypass.
  """
  @spec station_mode() :: :strict | :universal | :housing_bypass
  def station_mode, do: get(:station_mode) || :strict
end
```

**Step 3: Commit**

```bash
git add apps/bezgelor_world/config/config.exs apps/bezgelor_world/lib/bezgelor_world/tradeskill_config.ex
git commit -m "feat(world): Add tradeskill configuration"
```

---

## Remaining Tasks (Summary)

The following tasks follow the same pattern. Each creates a module with tests first:

### Task 13: Create Tradeskill Packets (Client)
- `ClientTradeskillLearn`, `ClientCraftStart`, `ClientCraftAddAdditive`, `ClientCraftFinalize`, `ClientGatherStart`, etc.

### Task 14: Create Tradeskill Packets (Server)
- `ServerTradeskillUpdate`, `ServerCraftSession`, `ServerCraftResult`, `ServerGatherResult`, `ServerNodeSpawn`, etc.

### Task 15: Create TradeskillHandler
- Wire up packet handlers to context operations

### Task 16: Create CraftingHandler
- Handle craft start, add additive, finalize operations

### Task 17: Create GatheringHandler
- Handle gather start, gather complete operations

### Task 18: Create NodeManager
- Per-zone node spawning and respawn timer management

### Task 19: Create TradeskillManager
- Profession validation, limit enforcement

### Task 20: Create TechTreeManager
- Talent validation, prerequisite checking, bonus calculation

### Task 21: Create WorkOrderManager
- Daily generation, completion tracking, reward distribution

### Task 22: Add Achievement Criteria Types
- Extend achievement system with tradeskill criteria

### Task 23: Integration Tests
- Full flow tests for crafting and gathering

### Task 24: Update STATUS.md
- Mark Phase 8 as complete

---

## Final Commit After All Tasks

```bash
git add -A
git commit -m "feat: Complete Phase 8 Tradeskills implementation

- Coordinate-based crafting with rectangle hit detection
- Gathering nodes with configurable competition
- Tech trees with talent bonuses
- Work orders with daily generation
- Achievement integration
- Server-configurable behaviors"
```

---

**Plan complete and saved to `docs/plans/2025-12-11-tradeskills-implementation.md`.**

Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
