# Phase 10: Dungeons & Instances - Implementation Plan

**Created:** 2025-12-11
**Design Document:** [phase10-dungeons-instances.md](./phase10-dungeons-instances.md)
**Status:** ~85% Complete - See Implementation Status below
**Last Review:** 2025-12-11

---

## Implementation Status Summary

| Category | Status | Details |
|----------|--------|---------|
| Database Migration | ✅ Complete | `20251211000000_create_instance_tables.exs` |
| Schemas (8) | ✅ Complete | All 8 schemas implemented |
| Context Modules (3) | ✅ Complete | instances.ex, group_finder.ex, lockouts.ex |
| Protocol Packets (31) | ✅ Complete | 22 server + 9 client packets |
| Static Data & ETS | ✅ Complete | JSON files and Store integration |
| Instance GenServer | ✅ Complete | instance.ex, instance_supervisor.ex, instance_registry.ex |
| Boss Encounter | ✅ Complete | boss_encounter.ex |
| GroupFinder GenServer | ✅ Complete | group_finder.ex with combined matcher.ex |
| LootManager GenServer | ✅ Complete | loot_manager.ex, loot_rules.ex |
| Handlers | ✅ Complete | group_finder_handler.ex, loot_handler.ex |
| **Supervision Tree** | ❌ **Missing** | GenServers not registered in application.ex |
| **LockoutManager** | ❌ **Missing** | Scheduled reset GenServer not implemented |
| **MythicManager** | ❌ **Missing** | Keystone/affix GenServer not implemented |
| **Sample Encounters** | ❌ **Missing** | No DSL-based encounters exist |
| **Schema Tests** | ❌ **Missing** | No Phase 10 schema unit tests |
| **Config Module** | ❌ **Missing** | No unified configuration module |

### Implementation Differences from Original Plan

| Original Plan | Actual Implementation |
|---------------|----------------------|
| 3 separate matchers (matcher_simple.ex, matcher_smart.ex, matcher_advanced.ex) | Combined into single `matcher.ex` with all 3 tiers |
| 4 separate loot modules (personal_loot.ex, need_greed.ex, master_loot.ex) | Combined into `loot_rules.ex` with all systems |
| boss_process.ex in encounter/ | Implemented as `boss_encounter.ex` in instance/ |

---

## Task Overview

| # | Task | Dependencies | Complexity | Status |
|---|------|--------------|------------|--------|
| 1 | Database Migration | None | Medium | ✅ |
| 2 | InstanceLockout Schema | Task 1 | Low | ✅ |
| 3 | InstanceCompletion Schema | Task 1 | Low | ✅ |
| 4 | InstanceSave Schema | Task 1 | Low | ✅ |
| 5 | GroupFinderQueue Schema | Task 1 | Low | ✅ |
| 6 | GroupFinderGroup Schema | Task 1 | Low | ✅ |
| 7 | MythicKeystone Schema | Task 1 | Low | ✅ |
| 8 | MythicRun Schema | Task 1 | Low | ✅ |
| 9 | LootHistory Schema | Task 1 | Low | ✅ |
| 10 | Instances Context Module | Tasks 2-4 | Medium | ✅ |
| 11 | GroupFinder Context Module | Tasks 5-6 | Medium | ✅ |
| 12 | Lockouts Context Module | Task 2 | Medium | ✅ |
| 13 | Static Data - instances.json | None | Low | ✅ |
| 14 | Static Data - instance_bosses.json | None | Medium | ✅ |
| 15 | Static Data - mythic_affixes.json | None | Low | ✅ |
| 16 | ETS Integration | Tasks 13-15 | Low | ✅ |
| 17 | Server Packets - Instance Info | None | Low | ✅ |
| 18 | Server Packets - Queue/Group | None | Low | ✅ |
| 19 | Server Packets - Encounter | None | Low | ✅ |
| 20 | Server Packets - Loot | None | Low | ✅ |
| 21 | Client Packets - Queue | None | Low | ✅ |
| 22 | Client Packets - Instance | None | Low | ✅ |
| 23 | Client Packets - Loot | None | Low | ✅ |
| 24 | Boss DSL - Core Module | None | High | ✅ |
| 25 | Boss DSL - Phase Primitives | Task 24 | Medium | ✅ |
| 26 | Boss DSL - Telegraph Primitives | Task 24 | Medium | ✅ |
| 27 | Boss DSL - Target Primitives | Task 24 | Medium | ✅ |
| 28 | Boss DSL - Spawn Primitives | Task 24 | Medium | ✅ |
| 29 | Boss DSL - Movement Primitives | Task 24 | Medium | ✅ |
| 30 | Boss DSL - Interrupt Primitives | Task 24 | Low | ✅ |
| 31 | Boss DSL - Environmental Primitives | Task 24 | Medium | ✅ |
| 32 | Boss DSL - Coordination Primitives | Task 24 | Medium | ✅ |
| 33 | BossProcess GenServer | Tasks 24-32 | High | ✅ (as boss_encounter.ex) |
| 34 | Instance GenServer | Task 16 | High | ✅ |
| 35 | InstanceSupervisor | Task 34 | Medium | ✅ |
| 36 | GroupFinder GenServer | Task 11 | High | ✅ |
| 37 | Matcher - Simple FIFO | Task 36 | Low | ✅ (combined in matcher.ex) |
| 38 | Matcher - Smart | Task 36 | Medium | ✅ (combined in matcher.ex) |
| 39 | Matcher - Advanced | Task 36 | Medium | ✅ (combined in matcher.ex) |
| 40 | LockoutManager GenServer | Task 12 | Medium | ❌ **MISSING** |
| 41 | LootManager GenServer | None | Medium | ✅ |
| 42 | Loot - Personal | Task 41 | Low | ✅ (in loot_rules.ex) |
| 43 | Loot - Need/Greed | Task 41 | Medium | ✅ (in loot_rules.ex) |
| 44 | Loot - Master Loot | Task 41 | Low | ✅ (in loot_rules.ex) |
| 45 | MythicManager GenServer | Tasks 7-8 | Medium | ❌ **MISSING** |
| 46 | Instance Handler | Tasks 17-19, 21-22, 34 | Medium | ✅ (integrated) |
| 47 | GroupFinder Handler | Tasks 18, 21, 36 | Medium | ✅ |
| 48 | Loot Handler | Tasks 20, 23, 41 | Medium | ✅ |
| 49 | Sample Encounter - Stormtalon | Tasks 24-33 | Medium | ❌ **MISSING** |
| 50 | Sample Encounter - KelVoreth | Tasks 24-33 | Medium | ❌ **MISSING** |
| 51 | Instance Entry/Exit System | Task 34 | Medium | ✅ |
| 52 | Role Validation Module | None | Low | ✅ |
| 53 | Configuration Module | None | Medium | ❌ **MISSING** |
| 54 | Supervision Tree Integration | Tasks 35, 36, 40, 41, 45 | Medium | ❌ **MISSING** |
| 55 | Tests - Schemas | Tasks 2-9 | Low | ❌ **MISSING** |
| 56 | Tests - DSL Compilation | Tasks 24-32 | Medium | ❌ Partial |
| 57 | Tests - Group Finder | Tasks 36-39 | Medium | ✅ |
| 58 | Tests - Lockouts | Task 40 | Medium | ❌ **MISSING** |
| 59 | Tests - Loot Distribution | Tasks 41-44 | Medium | ✅ |
| 60 | Update STATUS.md | All | Low | ⚠️ Needs update |

**Summary:** 51/60 tasks complete (~85%), 9 tasks remaining

---

## Detailed Task Specifications

### Task 1: Database Migration

**File:** `apps/bezgelor_db/priv/repo/migrations/2025XXXX_create_instance_tables.exs`

**Description:** Create all database tables for the instance system.

**Tables to create:**
- `instance_lockouts` - Character lockout tracking
- `instance_completions` - Historical completion records
- `instance_saves` - Raid save states (boss kills, progress)
- `group_finder_queue` - Active queue entries
- `group_finder_groups` - Formed groups awaiting entry
- `mythic_keystones` - Player keystone inventory
- `mythic_runs` - Completed mythic+ runs for leaderboards
- `loot_history` - Loot distribution audit trail

**Schema:**
```elixir
# instance_lockouts
create table(:instance_lockouts) do
  add :character_id, references(:characters, on_delete: :delete_all), null: false
  add :instance_type, :string, null: false  # dungeon, adventure, raid, expedition
  add :instance_definition_id, :integer, null: false
  add :difficulty, :string, null: false  # normal, veteran, challenge, mythic_plus
  add :instance_guid, :binary  # For raid instance locks
  add :boss_kills, {:array, :integer}, default: []  # For encounter locks
  add :loot_received_at, :utc_datetime
  add :loot_eligible, :boolean, default: true
  add :completion_count, :integer, default: 0  # For soft locks
  add :diminishing_factor, :float, default: 1.0
  add :extended, :boolean, default: false
  add :expires_at, :utc_datetime, null: false
  timestamps()
end

create index(:instance_lockouts, [:character_id])
create index(:instance_lockouts, [:character_id, :instance_definition_id, :difficulty])
create index(:instance_lockouts, [:expires_at])

# instance_completions
create table(:instance_completions) do
  add :character_id, references(:characters, on_delete: :delete_all), null: false
  add :instance_definition_id, :integer, null: false
  add :instance_type, :string, null: false
  add :difficulty, :string, null: false
  add :completed_at, :utc_datetime, null: false
  add :duration_seconds, :integer
  add :deaths, :integer, default: 0
  add :damage_done, :bigint, default: 0
  add :healing_done, :bigint, default: 0
  add :mythic_level, :integer  # For mythic+ runs
  add :timed, :boolean  # For mythic+ - beat the timer?
  timestamps()
end

create index(:instance_completions, [:character_id])
create index(:instance_completions, [:instance_definition_id, :difficulty])

# instance_saves
create table(:instance_saves) do
  add :instance_guid, :binary, null: false
  add :instance_definition_id, :integer, null: false
  add :difficulty, :string, null: false
  add :boss_kills, {:array, :integer}, default: []
  add :trash_cleared, {:array, :string}, default: []
  add :created_at, :utc_datetime, null: false
  add :expires_at, :utc_datetime, null: false
  timestamps()
end

create unique_index(:instance_saves, [:instance_guid])
create index(:instance_saves, [:expires_at])

# group_finder_queue
create table(:group_finder_queue) do
  add :character_id, references(:characters, on_delete: :delete_all), null: false
  add :account_id, references(:accounts, on_delete: :delete_all), null: false
  add :instance_type, :string, null: false
  add :instance_ids, {:array, :integer}, null: false  # Queued for which instances
  add :difficulty, :string, null: false
  add :role, :string, null: false  # tank, healer, dps
  add :gear_score, :integer, default: 0
  add :completion_rate, :float, default: 1.0
  add :preferences, :map, default: %{}  # voice_chat, learning_run, etc.
  add :queued_at, :utc_datetime, null: false
  add :estimated_wait_seconds, :integer
  timestamps()
end

create unique_index(:group_finder_queue, [:character_id])
create index(:group_finder_queue, [:instance_type, :difficulty, :role])
create index(:group_finder_queue, [:queued_at])

# group_finder_groups
create table(:group_finder_groups) do
  add :group_guid, :binary, null: false
  add :instance_definition_id, :integer, null: false
  add :difficulty, :string, null: false
  add :member_ids, {:array, :integer}, null: false
  add :roles, :map, null: false  # %{tank: [id], healer: [id], dps: [ids]}
  add :status, :string, default: "forming"  # forming, ready, entering, active
  add :ready_check, :map, default: %{}  # %{character_id => true/false}
  add :expires_at, :utc_datetime
  timestamps()
end

create unique_index(:group_finder_groups, [:group_guid])
create index(:group_finder_groups, [:status])

# mythic_keystones
create table(:mythic_keystones) do
  add :character_id, references(:characters, on_delete: :delete_all), null: false
  add :instance_definition_id, :integer, null: false
  add :level, :integer, null: false, default: 1
  add :affixes, {:array, :string}, default: []
  add :obtained_at, :utc_datetime, null: false
  add :depleted, :boolean, default: false
  timestamps()
end

create index(:mythic_keystones, [:character_id])

# mythic_runs
create table(:mythic_runs) do
  add :instance_definition_id, :integer, null: false
  add :level, :integer, null: false
  add :affixes, {:array, :string}, null: false
  add :duration_seconds, :integer, null: false
  add :timed, :boolean, null: false
  add :completed_at, :utc_datetime, null: false
  add :member_ids, {:array, :integer}, null: false
  add :member_names, {:array, :string}, null: false
  add :member_classes, {:array, :string}, null: false
  add :season, :integer, default: 1
  timestamps()
end

create index(:mythic_runs, [:instance_definition_id, :level])
create index(:mythic_runs, [:season, :instance_definition_id, :duration_seconds])

# loot_history
create table(:loot_history) do
  add :instance_guid, :binary
  add :character_id, references(:characters, on_delete: :nilify_all)
  add :item_id, :integer, null: false
  add :item_quality, :string
  add :source_type, :string  # boss, trash, chest
  add :source_id, :integer  # boss_id or creature_id
  add :distribution_method, :string  # personal, need, greed, master
  add :roll_value, :integer  # For need/greed
  add :awarded_at, :utc_datetime, null: false
  timestamps()
end

create index(:loot_history, [:instance_guid])
create index(:loot_history, [:character_id])
create index(:loot_history, [:awarded_at])
```

**Acceptance criteria:**
- [ ] Migration runs successfully
- [ ] All indexes created
- [ ] Foreign key constraints working
- [ ] Rollback works cleanly

---

### Task 2: InstanceLockout Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/instance_lockout.ex`

**Description:** Ecto schema for tracking character lockouts.

```elixir
defmodule BezgelorDb.Schema.InstanceLockout do
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
    id: integer() | nil,
    character_id: integer(),
    instance_type: String.t(),
    instance_definition_id: integer(),
    difficulty: String.t(),
    instance_guid: binary() | nil,
    boss_kills: [integer()],
    loot_received_at: DateTime.t() | nil,
    loot_eligible: boolean(),
    completion_count: integer(),
    diminishing_factor: float(),
    extended: boolean(),
    expires_at: DateTime.t(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "instance_lockouts" do
    belongs_to :character, Character

    field :instance_type, :string
    field :instance_definition_id, :integer
    field :difficulty, :string
    field :instance_guid, :binary
    field :boss_kills, {:array, :integer}, default: []
    field :loot_received_at, :utc_datetime
    field :loot_eligible, :boolean, default: true
    field :completion_count, :integer, default: 0
    field :diminishing_factor, :float, default: 1.0
    field :extended, :boolean, default: false
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:character_id, :instance_type, :instance_definition_id, :difficulty, :expires_at]
  @optional_fields [:instance_guid, :boss_kills, :loot_received_at, :loot_eligible,
                    :completion_count, :diminishing_factor, :extended]

  def changeset(lockout, attrs) do
    lockout
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, ~w(dungeon adventure raid expedition))
    |> validate_inclusion(:difficulty, ~w(normal veteran challenge mythic_plus))
    |> foreign_key_constraint(:character_id)
  end

  def record_boss_kill(lockout, boss_id) do
    new_kills = Enum.uniq([boss_id | lockout.boss_kills])
    change(lockout, boss_kills: new_kills)
  end

  def record_loot_received(lockout) do
    change(lockout, loot_received_at: DateTime.utc_now(), loot_eligible: false)
  end

  def extend(lockout) do
    change(lockout, extended: true)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Changeset validates required fields
- [ ] Helper functions work correctly
- [ ] Associations resolve properly

---

### Task 3: InstanceCompletion Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/instance_completion.ex`

**Description:** Ecto schema for historical completion records.

```elixir
defmodule BezgelorDb.Schema.InstanceCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
    id: integer() | nil,
    character_id: integer(),
    instance_definition_id: integer(),
    instance_type: String.t(),
    difficulty: String.t(),
    completed_at: DateTime.t(),
    duration_seconds: integer() | nil,
    deaths: integer(),
    damage_done: integer(),
    healing_done: integer(),
    mythic_level: integer() | nil,
    timed: boolean() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "instance_completions" do
    belongs_to :character, Character

    field :instance_definition_id, :integer
    field :instance_type, :string
    field :difficulty, :string
    field :completed_at, :utc_datetime
    field :duration_seconds, :integer
    field :deaths, :integer, default: 0
    field :damage_done, :integer, default: 0
    field :healing_done, :integer, default: 0
    field :mythic_level, :integer
    field :timed, :boolean

    timestamps()
  end

  @required_fields [:character_id, :instance_definition_id, :instance_type, :difficulty, :completed_at]
  @optional_fields [:duration_seconds, :deaths, :damage_done, :healing_done, :mythic_level, :timed]

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, ~w(dungeon adventure raid expedition))
    |> validate_inclusion(:difficulty, ~w(normal veteran challenge mythic_plus))
    |> validate_number(:deaths, greater_than_or_equal_to: 0)
    |> validate_number(:damage_done, greater_than_or_equal_to: 0)
    |> validate_number(:healing_done, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Changeset validates all fields
- [ ] Number validations work correctly

---

### Task 4: InstanceSave Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/instance_save.ex`

**Description:** Ecto schema for raid save states.

```elixir
defmodule BezgelorDb.Schema.InstanceSave do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer() | nil,
    instance_guid: binary(),
    instance_definition_id: integer(),
    difficulty: String.t(),
    boss_kills: [integer()],
    trash_cleared: [String.t()],
    created_at: DateTime.t(),
    expires_at: DateTime.t(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "instance_saves" do
    field :instance_guid, :binary
    field :instance_definition_id, :integer
    field :difficulty, :string
    field :boss_kills, {:array, :integer}, default: []
    field :trash_cleared, {:array, :string}, default: []
    field :created_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:instance_guid, :instance_definition_id, :difficulty, :created_at, :expires_at]
  @optional_fields [:boss_kills, :trash_cleared]

  def changeset(save, attrs) do
    save
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:difficulty, ~w(normal veteran))
    |> unique_constraint(:instance_guid)
  end

  def record_boss_kill(save, boss_id) do
    new_kills = Enum.uniq([boss_id | save.boss_kills])
    change(save, boss_kills: new_kills)
  end

  def record_trash_cleared(save, area_id) do
    new_cleared = Enum.uniq([area_id | save.trash_cleared])
    change(save, trash_cleared: new_cleared)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Unique constraint on instance_guid works
- [ ] Helper functions work correctly

---

### Task 5: GroupFinderQueue Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/group_finder_queue.ex`

**Description:** Ecto schema for queue entries.

```elixir
defmodule BezgelorDb.Schema.GroupFinderQueue do
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Account, Character}

  @type t :: %__MODULE__{
    id: integer() | nil,
    character_id: integer(),
    account_id: integer(),
    instance_type: String.t(),
    instance_ids: [integer()],
    difficulty: String.t(),
    role: String.t(),
    gear_score: integer(),
    completion_rate: float(),
    preferences: map(),
    queued_at: DateTime.t(),
    estimated_wait_seconds: integer() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "group_finder_queue" do
    belongs_to :character, Character
    belongs_to :account, Account

    field :instance_type, :string
    field :instance_ids, {:array, :integer}
    field :difficulty, :string
    field :role, :string
    field :gear_score, :integer, default: 0
    field :completion_rate, :float, default: 1.0
    field :preferences, :map, default: %{}
    field :queued_at, :utc_datetime
    field :estimated_wait_seconds, :integer

    timestamps()
  end

  @required_fields [:character_id, :account_id, :instance_type, :instance_ids, :difficulty, :role, :queued_at]
  @optional_fields [:gear_score, :completion_rate, :preferences, :estimated_wait_seconds]

  def changeset(queue_entry, attrs) do
    queue_entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, ~w(dungeon adventure raid expedition))
    |> validate_inclusion(:difficulty, ~w(normal veteran challenge mythic_plus))
    |> validate_inclusion(:role, ~w(tank healer dps))
    |> validate_number(:gear_score, greater_than_or_equal_to: 0)
    |> validate_number(:completion_rate, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_length(:instance_ids, min: 1)
    |> unique_constraint(:character_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:account_id)
  end

  def update_estimate(queue_entry, seconds) do
    change(queue_entry, estimated_wait_seconds: seconds)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Unique constraint on character_id prevents double-queueing
- [ ] All validations work correctly

---

### Task 6: GroupFinderGroup Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/group_finder_group.ex`

**Description:** Ecto schema for formed groups.

```elixir
defmodule BezgelorDb.Schema.GroupFinderGroup do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer() | nil,
    group_guid: binary(),
    instance_definition_id: integer(),
    difficulty: String.t(),
    member_ids: [integer()],
    roles: map(),
    status: String.t(),
    ready_check: map(),
    expires_at: DateTime.t() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "group_finder_groups" do
    field :group_guid, :binary
    field :instance_definition_id, :integer
    field :difficulty, :string
    field :member_ids, {:array, :integer}
    field :roles, :map
    field :status, :string, default: "forming"
    field :ready_check, :map, default: %{}
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:group_guid, :instance_definition_id, :difficulty, :member_ids, :roles]
  @optional_fields [:status, :ready_check, :expires_at]

  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:difficulty, ~w(normal veteran challenge mythic_plus))
    |> validate_inclusion(:status, ~w(forming ready entering active disbanded))
    |> unique_constraint(:group_guid)
  end

  def set_ready(group, character_id, ready) do
    new_ready_check = Map.put(group.ready_check, to_string(character_id), ready)
    change(group, ready_check: new_ready_check)
  end

  def all_ready?(%__MODULE__{member_ids: member_ids, ready_check: ready_check}) do
    Enum.all?(member_ids, fn id ->
      Map.get(ready_check, to_string(id), false) == true
    end)
  end

  def set_status(group, status) do
    change(group, status: status)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Ready check tracking works correctly
- [ ] Status transitions work properly

---

### Task 7: MythicKeystone Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/mythic_keystone.ex`

**Description:** Ecto schema for player keystone inventory.

```elixir
defmodule BezgelorDb.Schema.MythicKeystone do
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
    id: integer() | nil,
    character_id: integer(),
    instance_definition_id: integer(),
    level: integer(),
    affixes: [String.t()],
    obtained_at: DateTime.t(),
    depleted: boolean(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "mythic_keystones" do
    belongs_to :character, Character

    field :instance_definition_id, :integer
    field :level, :integer, default: 1
    field :affixes, {:array, :string}, default: []
    field :obtained_at, :utc_datetime
    field :depleted, :boolean, default: false

    timestamps()
  end

  @required_fields [:character_id, :instance_definition_id, :level, :obtained_at]
  @optional_fields [:affixes, :depleted]

  def changeset(keystone, attrs) do
    keystone
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:level, greater_than: 0, less_than_or_equal_to: 30)
    |> foreign_key_constraint(:character_id)
  end

  def upgrade(keystone, levels \\ 1) do
    new_level = min(keystone.level + levels, 30)
    change(keystone, level: new_level, depleted: false)
  end

  def deplete(keystone) do
    new_level = max(keystone.level - 1, 1)
    change(keystone, level: new_level, depleted: true)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Level validation works (1-30)
- [ ] Upgrade/deplete helpers work correctly

---

### Task 8: MythicRun Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/mythic_run.ex`

**Description:** Ecto schema for mythic+ run history/leaderboards.

```elixir
defmodule BezgelorDb.Schema.MythicRun do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer() | nil,
    instance_definition_id: integer(),
    level: integer(),
    affixes: [String.t()],
    duration_seconds: integer(),
    timed: boolean(),
    completed_at: DateTime.t(),
    member_ids: [integer()],
    member_names: [String.t()],
    member_classes: [String.t()],
    season: integer(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "mythic_runs" do
    field :instance_definition_id, :integer
    field :level, :integer
    field :affixes, {:array, :string}
    field :duration_seconds, :integer
    field :timed, :boolean
    field :completed_at, :utc_datetime
    field :member_ids, {:array, :integer}
    field :member_names, {:array, :string}
    field :member_classes, {:array, :string}
    field :season, :integer, default: 1

    timestamps()
  end

  @required_fields [:instance_definition_id, :level, :affixes, :duration_seconds, :timed,
                    :completed_at, :member_ids, :member_names, :member_classes]
  @optional_fields [:season]

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:level, greater_than: 0)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_length(:member_ids, min: 1, max: 5)
    |> validate_length(:member_names, min: 1, max: 5)
    |> validate_length(:member_classes, min: 1, max: 5)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] All validations work correctly

---

### Task 9: LootHistory Schema

**File:** `apps/bezgelor_db/lib/bezgelor_db/schema/loot_history.ex`

**Description:** Ecto schema for loot distribution audit trail.

```elixir
defmodule BezgelorDb.Schema.LootHistory do
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
    id: integer() | nil,
    instance_guid: binary() | nil,
    character_id: integer() | nil,
    item_id: integer(),
    item_quality: String.t() | nil,
    source_type: String.t() | nil,
    source_id: integer() | nil,
    distribution_method: String.t() | nil,
    roll_value: integer() | nil,
    awarded_at: DateTime.t(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "loot_history" do
    belongs_to :character, Character

    field :instance_guid, :binary
    field :item_id, :integer
    field :item_quality, :string
    field :source_type, :string
    field :source_id, :integer
    field :distribution_method, :string
    field :roll_value, :integer
    field :awarded_at, :utc_datetime

    timestamps()
  end

  @required_fields [:item_id, :awarded_at]
  @optional_fields [:instance_guid, :character_id, :item_quality, :source_type,
                    :source_id, :distribution_method, :roll_value]

  def changeset(history, attrs) do
    history
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_type, ~w(boss trash chest))
    |> validate_inclusion(:distribution_method, ~w(personal need greed master round_robin))
    |> validate_number(:roll_value, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:character_id)
  end
end
```

**Acceptance criteria:**
- [ ] Schema compiles without warnings
- [ ] Optional fields handled correctly (character can be nil for unclaimed loot)

---

### Task 10: Instances Context Module

**File:** `apps/bezgelor_db/lib/bezgelor_db/instances.ex`

**Description:** Context module for instance management operations.

```elixir
defmodule BezgelorDb.Instances do
  @moduledoc """
  Context for instance-related database operations.

  Handles instance saves, completions, and related queries.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{InstanceSave, InstanceCompletion}

  # Instance Saves

  @doc "Get or create an instance save by GUID"
  @spec get_or_create_save(binary(), integer(), String.t()) :: {:ok, InstanceSave.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_save(instance_guid, definition_id, difficulty) do
    case get_save(instance_guid) do
      nil -> create_save(instance_guid, definition_id, difficulty)
      save -> {:ok, save}
    end
  end

  @doc "Get an instance save by GUID"
  @spec get_save(binary()) :: InstanceSave.t() | nil
  def get_save(instance_guid) do
    Repo.get_by(InstanceSave, instance_guid: instance_guid)
  end

  @doc "Create a new instance save"
  @spec create_save(binary(), integer(), String.t()) :: {:ok, InstanceSave.t()} | {:error, Ecto.Changeset.t()}
  def create_save(instance_guid, definition_id, difficulty) do
    now = DateTime.utc_now()
    # Default expiry is next weekly reset (Tuesday 10 AM)
    expires_at = calculate_next_weekly_reset(now)

    %InstanceSave{}
    |> InstanceSave.changeset(%{
      instance_guid: instance_guid,
      instance_definition_id: definition_id,
      difficulty: difficulty,
      created_at: now,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc "Record a boss kill in an instance save"
  @spec record_boss_kill(binary(), integer()) :: {:ok, InstanceSave.t()} | {:error, term()}
  def record_boss_kill(instance_guid, boss_id) do
    case get_save(instance_guid) do
      nil -> {:error, :save_not_found}
      save ->
        save
        |> InstanceSave.record_boss_kill(boss_id)
        |> Repo.update()
    end
  end

  @doc "Delete expired saves"
  @spec cleanup_expired_saves() :: {integer(), nil}
  def cleanup_expired_saves do
    now = DateTime.utc_now()

    from(s in InstanceSave, where: s.expires_at < ^now)
    |> Repo.delete_all()
  end

  # Instance Completions

  @doc "Record an instance completion"
  @spec record_completion(map()) :: {:ok, InstanceCompletion.t()} | {:error, Ecto.Changeset.t()}
  def record_completion(attrs) do
    %InstanceCompletion{}
    |> InstanceCompletion.changeset(Map.put(attrs, :completed_at, DateTime.utc_now()))
    |> Repo.insert()
  end

  @doc "Get completion count for a character/instance"
  @spec get_completion_count(integer(), integer(), String.t()) :: integer()
  def get_completion_count(character_id, instance_id, difficulty) do
    from(c in InstanceCompletion,
      where: c.character_id == ^character_id and
             c.instance_definition_id == ^instance_id and
             c.difficulty == ^difficulty,
      select: count(c.id)
    )
    |> Repo.one()
  end

  @doc "Get completion rate for a character (for smart matching)"
  @spec get_completion_rate(integer()) :: float()
  def get_completion_rate(character_id) do
    # Calculate ratio of completions to attempts (simplified)
    # A more sophisticated version would track abandons
    total = from(c in InstanceCompletion, where: c.character_id == ^character_id, select: count(c.id))
            |> Repo.one()

    if total == 0, do: 1.0, else: 1.0  # Simplified - always 100% if they have completions
  end

  @doc "Get best mythic+ times for leaderboard"
  @spec get_leaderboard(integer(), integer(), integer()) :: [MythicRun.t()]
  def get_leaderboard(instance_id, level, limit \\ 100) do
    alias BezgelorDb.Schema.MythicRun

    from(r in MythicRun,
      where: r.instance_definition_id == ^instance_id and r.level == ^level and r.timed == true,
      order_by: [asc: r.duration_seconds],
      limit: ^limit
    )
    |> Repo.all()
  end

  # Helper functions

  defp calculate_next_weekly_reset(now) do
    # Find next Tuesday at 10:00 AM
    days_until_tuesday = rem(9 - Date.day_of_week(now), 7)
    days_until_tuesday = if days_until_tuesday == 0 and now.hour >= 10, do: 7, else: days_until_tuesday

    now
    |> DateTime.add(days_until_tuesday * 24 * 60 * 60, :second)
    |> Map.put(:hour, 10)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end
end
```

**Acceptance criteria:**
- [ ] All functions compile without warnings
- [ ] Save get/create works correctly
- [ ] Boss kill recording works
- [ ] Completion recording and queries work
- [ ] Weekly reset calculation is correct

---

### Task 11: GroupFinder Context Module

**File:** `apps/bezgelor_db/lib/bezgelor_db/group_finder.ex`

**Description:** Context module for group finder queue operations.

```elixir
defmodule BezgelorDb.GroupFinder do
  @moduledoc """
  Context for group finder queue and group operations.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{GroupFinderQueue, GroupFinderGroup}

  # Queue Operations

  @doc "Add a player to the queue"
  @spec enqueue(map()) :: {:ok, GroupFinderQueue.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(attrs) do
    attrs = Map.put(attrs, :queued_at, DateTime.utc_now())

    %GroupFinderQueue{}
    |> GroupFinderQueue.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :character_id)
  end

  @doc "Remove a player from the queue"
  @spec dequeue(integer()) :: {:ok, GroupFinderQueue.t()} | {:error, :not_found}
  def dequeue(character_id) do
    case Repo.get_by(GroupFinderQueue, character_id: character_id) do
      nil -> {:error, :not_found}
      entry ->
        Repo.delete(entry)
        {:ok, entry}
    end
  end

  @doc "Get queue entry for a character"
  @spec get_queue_entry(integer()) :: GroupFinderQueue.t() | nil
  def get_queue_entry(character_id) do
    Repo.get_by(GroupFinderQueue, character_id: character_id)
  end

  @doc "Check if character is in queue"
  @spec in_queue?(integer()) :: boolean()
  def in_queue?(character_id) do
    get_queue_entry(character_id) != nil
  end

  @doc "Get queued players for an instance type, difficulty, and role"
  @spec get_queued_for_role(String.t(), String.t(), String.t(), integer()) :: [GroupFinderQueue.t()]
  def get_queued_for_role(instance_type, difficulty, role, limit \\ 100) do
    from(q in GroupFinderQueue,
      where: q.instance_type == ^instance_type and
             q.difficulty == ^difficulty and
             q.role == ^role,
      order_by: [asc: q.queued_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Get all queued players for an instance"
  @spec get_queued_for_instance(integer(), String.t()) :: [GroupFinderQueue.t()]
  def get_queued_for_instance(instance_id, difficulty) do
    from(q in GroupFinderQueue,
      where: ^instance_id in q.instance_ids and q.difficulty == ^difficulty,
      order_by: [asc: q.queued_at]
    )
    |> Repo.all()
  end

  @doc "Update queue wait time estimate"
  @spec update_wait_estimate(integer(), integer()) :: {:ok, GroupFinderQueue.t()} | {:error, term()}
  def update_wait_estimate(character_id, seconds) do
    case get_queue_entry(character_id) do
      nil -> {:error, :not_found}
      entry ->
        entry
        |> GroupFinderQueue.update_estimate(seconds)
        |> Repo.update()
    end
  end

  # Group Operations

  @doc "Create a formed group"
  @spec create_group(map()) :: {:ok, GroupFinderGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_group(attrs) do
    attrs = Map.put_new(attrs, :group_guid, generate_guid())

    %GroupFinderGroup{}
    |> GroupFinderGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get a group by GUID"
  @spec get_group(binary()) :: GroupFinderGroup.t() | nil
  def get_group(group_guid) do
    Repo.get_by(GroupFinderGroup, group_guid: group_guid)
  end

  @doc "Get group for a character"
  @spec get_group_for_character(integer()) :: GroupFinderGroup.t() | nil
  def get_group_for_character(character_id) do
    from(g in GroupFinderGroup,
      where: ^character_id in g.member_ids and g.status != "disbanded"
    )
    |> Repo.one()
  end

  @doc "Set player ready status"
  @spec set_ready(binary(), integer(), boolean()) :: {:ok, GroupFinderGroup.t()} | {:error, term()}
  def set_ready(group_guid, character_id, ready) do
    case get_group(group_guid) do
      nil -> {:error, :group_not_found}
      group ->
        group
        |> GroupFinderGroup.set_ready(character_id, ready)
        |> Repo.update()
    end
  end

  @doc "Update group status"
  @spec set_group_status(binary(), String.t()) :: {:ok, GroupFinderGroup.t()} | {:error, term()}
  def set_group_status(group_guid, status) do
    case get_group(group_guid) do
      nil -> {:error, :group_not_found}
      group ->
        group
        |> GroupFinderGroup.set_status(status)
        |> Repo.update()
    end
  end

  @doc "Disband a group and return members to queue (optional)"
  @spec disband_group(binary(), boolean()) :: :ok | {:error, term()}
  def disband_group(group_guid, requeue_members \\ false) do
    case get_group(group_guid) do
      nil -> {:error, :group_not_found}
      group ->
        if requeue_members do
          # TODO: Re-add members to queue with their original settings
        end

        group
        |> GroupFinderGroup.set_status("disbanded")
        |> Repo.update()

        :ok
    end
  end

  @doc "Cleanup old disbanded/expired groups"
  @spec cleanup_groups() :: {integer(), nil}
  def cleanup_groups do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour old

    from(g in GroupFinderGroup,
      where: g.status == "disbanded" or
             (not is_nil(g.expires_at) and g.expires_at < ^DateTime.utc_now()) or
             g.inserted_at < ^cutoff
    )
    |> Repo.delete_all()
  end

  # Private helpers

  defp generate_guid do
    :crypto.strong_rand_bytes(16)
  end
end
```

**Acceptance criteria:**
- [ ] All queue operations work correctly
- [ ] Group formation and status tracking work
- [ ] Ready check functionality works
- [ ] Cleanup removes old groups

---

### Task 12: Lockouts Context Module

**File:** `apps/bezgelor_db/lib/bezgelor_db/lockouts.ex`

**Description:** Context module for lockout operations.

```elixir
defmodule BezgelorDb.Lockouts do
  @moduledoc """
  Context for instance lockout management.

  Handles checking, creating, and managing lockouts for all content types.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.InstanceLockout

  @doc "Check if character is locked out of an instance"
  @spec locked_out?(integer(), integer(), String.t()) :: boolean()
  def locked_out?(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> false
      lockout -> not InstanceLockout.expired?(lockout)
    end
  end

  @doc "Get lockout for character/instance/difficulty"
  @spec get_lockout(integer(), integer(), String.t()) :: InstanceLockout.t() | nil
  def get_lockout(character_id, instance_id, difficulty) do
    from(l in InstanceLockout,
      where: l.character_id == ^character_id and
             l.instance_definition_id == ^instance_id and
             l.difficulty == ^difficulty and
             l.expires_at > ^DateTime.utc_now()
    )
    |> Repo.one()
  end

  @doc "Get all active lockouts for a character"
  @spec get_character_lockouts(integer()) :: [InstanceLockout.t()]
  def get_character_lockouts(character_id) do
    from(l in InstanceLockout,
      where: l.character_id == ^character_id and l.expires_at > ^DateTime.utc_now(),
      order_by: [asc: l.expires_at]
    )
    |> Repo.all()
  end

  @doc "Create or update a lockout"
  @spec create_or_update_lockout(map()) :: {:ok, InstanceLockout.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_lockout(attrs) do
    case get_lockout(attrs.character_id, attrs.instance_definition_id, attrs.difficulty) do
      nil ->
        %InstanceLockout{}
        |> InstanceLockout.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> InstanceLockout.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Record a boss kill in a lockout"
  @spec record_boss_kill(integer(), integer(), String.t(), integer()) :: {:ok, InstanceLockout.t()} | {:error, term()}
  def record_boss_kill(character_id, instance_id, difficulty, boss_id) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> {:error, :no_lockout}
      lockout ->
        lockout
        |> InstanceLockout.record_boss_kill(boss_id)
        |> Repo.update()
    end
  end

  @doc "Check if a specific boss has been killed"
  @spec boss_killed?(integer(), integer(), String.t(), integer()) :: boolean()
  def boss_killed?(character_id, instance_id, difficulty, boss_id) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> false
      lockout -> boss_id in lockout.boss_kills
    end
  end

  @doc "Mark loot as received (for loot lockouts)"
  @spec mark_loot_received(integer(), integer(), String.t()) :: {:ok, InstanceLockout.t()} | {:error, term()}
  def mark_loot_received(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> {:error, :no_lockout}
      lockout ->
        lockout
        |> InstanceLockout.record_loot_received()
        |> Repo.update()
    end
  end

  @doc "Check if character is eligible for loot"
  @spec loot_eligible?(integer(), integer(), String.t()) :: boolean()
  def loot_eligible?(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> true  # No lockout = eligible
      lockout -> lockout.loot_eligible
    end
  end

  @doc "Increment completion count (for soft lockouts)"
  @spec increment_completion(integer(), integer(), String.t()) :: {:ok, InstanceLockout.t()} | {:error, term()}
  def increment_completion(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> {:error, :no_lockout}
      lockout ->
        config = get_lockout_config(lockout.instance_type)
        new_count = lockout.completion_count + 1

        new_factor =
          if new_count > Map.get(config, :diminishing_start, 5) do
            lockout.diminishing_factor * Map.get(config, :diminishing_factor, 0.8)
          else
            lockout.diminishing_factor
          end

        lockout
        |> Ecto.Changeset.change(completion_count: new_count, diminishing_factor: new_factor)
        |> Repo.update()
    end
  end

  @doc "Get diminishing returns factor for rewards"
  @spec get_reward_factor(integer(), integer(), String.t()) :: float()
  def get_reward_factor(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> 1.0
      lockout -> lockout.diminishing_factor
    end
  end

  @doc "Extend a lockout (player choice to keep save)"
  @spec extend_lockout(integer(), integer(), String.t()) :: {:ok, InstanceLockout.t()} | {:error, term()}
  def extend_lockout(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> {:error, :no_lockout}
      lockout ->
        # Add another week
        new_expires = DateTime.add(lockout.expires_at, 7 * 24 * 60 * 60, :second)

        lockout
        |> Ecto.Changeset.change(expires_at: new_expires, extended: true)
        |> Repo.update()
    end
  end

  @doc "Cleanup expired lockouts"
  @spec cleanup_expired() :: {integer(), nil}
  def cleanup_expired do
    from(l in InstanceLockout, where: l.expires_at < ^DateTime.utc_now())
    |> Repo.delete_all()
  end

  # Private helpers

  defp get_lockout_config(instance_type) do
    Application.get_env(:bezgelor_world, :lockouts, %{})
    |> Map.get(:rules, %{})
    |> Map.get(String.to_atom(instance_type), %{})
  end
end
```

**Acceptance criteria:**
- [ ] Lockout checking works for all lockout types
- [ ] Boss kill tracking works
- [ ] Loot eligibility tracking works
- [ ] Soft lockout diminishing returns work
- [ ] Lockout extension works

---

### Tasks 13-16: Static Data & ETS Integration

**Task 13 File:** `apps/bezgelor_data/priv/data/instances.json`
**Task 14 File:** `apps/bezgelor_data/priv/data/instance_bosses.json`
**Task 15 File:** `apps/bezgelor_data/priv/data/mythic_affixes.json`
**Task 16 File:** Update `apps/bezgelor_data/lib/bezgelor_data/store.ex`

See detailed JSON schemas and ETS query functions in design document.

---

### Tasks 17-23: Protocol Packets

Create client and server packets following the existing pattern in `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/`.

**Server Packets (Tasks 17-20):**
- `ServerInstanceInfo` - Instance details sent to player
- `ServerInstanceList` - Available instances for queuing
- `ServerGroupFormed` - Group formed notification
- `ServerQueueUpdate` - Queue position and ETA
- `ServerEncounterStart` - Boss encounter begins
- `ServerEncounterEnd` - Boss encounter ends (kill/wipe)
- `ServerLootDropInstance` - Loot drop notification
- `ServerLootRoll` - Need/greed roll UI

**Client Packets (Tasks 21-23):**
- `ClientQueueJoin` - Join group finder queue
- `ClientQueueLeave` - Leave queue
- `ClientQueueReady` - Accept/decline queue pop
- `ClientEnterInstance` - Request teleport into instance
- `ClientLeaveInstance` - Request to leave instance
- `ClientLootRoll` - Submit need/greed/pass choice
- `ClientResetInstance` - Request instance reset (leader)

---

### Tasks 24-32: Boss DSL Implementation

**Task 24 File:** `apps/bezgelor_world/lib/bezgelor_world/encounter/dsl.ex`

The DSL module provides macros for declarative boss encounter definition. See design document for complete DSL specification.

**Primitive Modules (Tasks 25-32):**
- `encounter/primitives/phase.ex` - Phase transitions, inheritance
- `encounter/primitives/telegraph.ex` - AoE shapes and rendering
- `encounter/primitives/target.ex` - Target selection algorithms
- `encounter/primitives/spawn.ex` - Add creature spawning
- `encounter/primitives/movement.ex` - Boss movement abilities
- `encounter/primitives/interrupt.ex` - Interrupt armor system
- `encounter/primitives/environmental.ex` - Hazards, terrain
- `encounter/primitives/coordination.ex` - Stack, spread, pair mechanics

---

### Tasks 33-35: Instance Process Architecture

**Task 33 File:** `apps/bezgelor_world/lib/bezgelor_world/encounter/boss_process.ex`

GenServer for running boss encounters with phase state machine.

**Task 34 File:** `apps/bezgelor_world/lib/bezgelor_world/instance/instance.ex`

GenServer for instance state management (players, bosses, loot).

**Task 35 File:** `apps/bezgelor_world/lib/bezgelor_world/instance/instance_supervisor.ex`

DynamicSupervisor for spawning instance processes.

---

### Tasks 36-39: Group Finder Implementation

**Task 36 File:** `apps/bezgelor_world/lib/bezgelor_world/group_finder/group_finder.ex`

Main GenServer for queue processing and group formation.

**Task 37 File:** `apps/bezgelor_world/lib/bezgelor_world/group_finder/matcher_simple.ex`

Tier 1 FIFO matching algorithm.

**Task 38 File:** `apps/bezgelor_world/lib/bezgelor_world/group_finder/matcher_smart.ex`

Tier 2 weighted matching algorithm.

**Task 39 File:** `apps/bezgelor_world/lib/bezgelor_world/group_finder/matcher_advanced.ex`

Tier 3 advanced matching with preferences and synergy.

---

### Tasks 40-45: Manager GenServers

**Task 40:** LockoutManager - Lockout reset scheduling
**Task 41:** LootManager - Loot distribution coordination
**Task 42-44:** Personal, Need/Greed, Master loot implementations
**Task 45:** MythicManager - Keystone and affix management

---

### Tasks 46-48: Packet Handlers

**Task 46 File:** `apps/bezgelor_world/lib/bezgelor_world/handler/instance_handler.ex`
**Task 47 File:** `apps/bezgelor_world/lib/bezgelor_world/handler/group_finder_handler.ex`
**Task 48 File:** `apps/bezgelor_world/lib/bezgelor_world/handler/loot_handler.ex`

---

### Tasks 49-50: Sample Encounters

**Task 49 File:** `apps/bezgelor_world/lib/bezgelor_world/encounter/encounters/stormtalon.ex`
**Task 50 File:** `apps/bezgelor_world/lib/bezgelor_world/encounter/encounters/kel_voreth_overlord.ex`

---

### Tasks 51-54: Integration

**Task 51:** Instance entry/exit teleportation system
**Task 52:** Role validation module
**Task 53:** Configuration consolidation module
**Task 54:** Supervision tree integration

---

### Tasks 55-60: Testing & Documentation

**Task 55-59:** Test suites for schemas, DSL, group finder, lockouts, loot
**Task 60:** Update STATUS.md

---

## Execution Order

**Phase A: Foundation (Tasks 1-12)**
Database and context modules - no runtime dependencies.

**Phase B: Static Data (Tasks 13-16)**
JSON definitions and ETS integration.

**Phase C: Protocol (Tasks 17-23)**
Packet definitions for all operations.

**Phase D: Boss System (Tasks 24-33)**
DSL and encounter runtime.

**Phase E: Instance Management (Tasks 34-35, 40-45)**
Instance and manager GenServers.

**Phase F: Group Finder (Tasks 36-39, 47)**
Queue processing and matching.

**Phase G: Handlers (Tasks 46, 48)**
Packet handlers.

**Phase H: Polish (Tasks 49-54)**
Sample content, entry/exit, configuration.

**Phase I: Testing (Tasks 55-60)**
Test suites and documentation.

---

## Success Metrics

1. Players can queue and get matched into instances
2. Boss encounters run with phases and mechanics
3. Lockouts properly restrict re-entry
4. Loot distributes according to configured rules
5. Mythic+ keystones upgrade/deplete correctly
6. All systems fully configurable via runtime config
