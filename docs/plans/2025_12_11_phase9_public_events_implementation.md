# Phase 9: Public Events Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement WildStar's complete public events system including zone events, world bosses, participation tracking, and scaled rewards.

**Architecture:** EventManager GenServer coordinates all events. Zone.Instance handles entity spawning and broadcasts. PublicEvents context manages database persistence. Static data loaded from JSON into ETS.

**Tech Stack:** Elixir, Ecto, GenServer, ETS, Phoenix.PubSub, Process.send_after (timers)

**Design Doc:** See `docs/plans/2025-12-11-phase9-public-events-design.md` for full architecture.

**Status:** ~92% Complete (24/26 tasks)
**Last Review:** 2025-12-11

---

## Implementation Status Summary

| Category | Complete | Total | Notes |
|----------|----------|-------|-------|
| Database Schemas | 5 | 5 | All event schemas implemented |
| Context Modules | 3 | 3 | Core, Participation, Scheduling |
| Static Data | 3 | 4 | Missing event_loot_tables.json |
| Server Packets | 11 | 12 | Missing ServerEventWave, ServerRewardTierUpdate |
| Client Packets | 4 | 4 | All complete |
| GenServers | 3 | 3 | EventManager, EventScheduler, EventManagerSupervisor |
| Handler | 1 | 1 | EventHandler complete |
| Tests | 1 | 2 | EventManager tests; missing schema tests |

---

## Task Overview

| # | Task | Description | Status |
|---|------|-------------|--------|
| 1 | Migration | Create database tables | ✅ Complete |
| 2 | EventInstance Schema | Active event tracking | ✅ Complete |
| 3 | EventParticipation Schema | Player contribution tracking | ✅ Complete |
| 4 | EventCompletion Schema | Historical completions | ✅ Complete |
| 5 | EventSchedule Schema | Event scheduling | ✅ Complete |
| 6 | WorldBossSpawn Schema | World boss spawn tracking | ✅ Complete |
| 7 | PublicEvents Context - Core | Instance lifecycle | ✅ Complete |
| 8 | PublicEvents Context - Participation | Join/contribute/rewards | ✅ Complete |
| 9 | PublicEvents Context - Scheduling | Schedule management | ✅ Complete |
| 10 | Static Data Files | JSON event definitions | ⚠️ 75% (missing loot tables) |
| 11 | ETS Integration | Load static data | ✅ Complete |
| 12 | Server Packets - Events | Start/update/complete packets | ⚠️ 83% (missing wave/tier) |
| 13 | Server Packets - World Boss | Boss-specific packets | ✅ Complete |
| 14 | Client Packets | Request packets | ✅ Complete |
| 15 | EventManager GenServer - Core | Basic lifecycle | ✅ Complete |
| 16 | EventManager - Objectives | Kill/collect tracking | ✅ Complete |
| 17 | EventManager - Scheduling | Timer-based triggers | ✅ Complete |
| 18 | EventManager - World Bosses | Boss spawn management | ✅ Complete |
| 19 | EventManager - Waves | Invasion wave system | ✅ Complete |
| 20 | EventManager - Territory | Control point mechanics | ✅ Complete |
| 21 | EventManager - Rewards | Tier calculation & distribution | ✅ Complete |
| 22 | Event Handler | Packet processing | ✅ Complete |
| 23 | Supervision Tree | Add to application | ✅ Complete |
| 24 | Combat Integration | Kill recording | ✅ Complete |
| 25 | Tests | Comprehensive test suite | ⚠️ 50% (missing schema tests) |
| 26 | Update STATUS.md | Mark Phase 9 complete | ✅ Complete |

---

## Missing Items

### 1. ServerEventWave Packet

Notifies clients of wave progression in invasion events.

```elixir
# apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_wave.ex
defmodule BezgelorProtocol.Packets.World.ServerEventWave do
  @moduledoc "Wave progression update for invasion events."
  use BezgelorProtocol.Packet, id: 0x0XXX  # TODO: Determine opcode

  defstruct [:event_instance_id, :wave_number, :total_waves, :enemies_spawned, :enemies_remaining]

  @impl true
  def write(packet) do
    <<
      packet.event_instance_id::little-32,
      packet.wave_number::8,
      packet.total_waves::8,
      packet.enemies_spawned::little-16,
      packet.enemies_remaining::little-16
    >>
  end
end
```

### 2. ServerRewardTierUpdate Packet

Notifies client when their reward tier changes during an event.

```elixir
# apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_reward_tier_update.ex
defmodule BezgelorProtocol.Packets.World.ServerRewardTierUpdate do
  @moduledoc "Reward tier change notification."
  use BezgelorProtocol.Packet, id: 0x0XXX  # TODO: Determine opcode

  @tiers %{participation: 0, bronze: 1, silver: 2, gold: 3}

  defstruct [:event_instance_id, :tier, :contribution_score]

  @impl true
  def write(packet) do
    tier_id = Map.get(@tiers, packet.tier, 0)
    <<
      packet.event_instance_id::little-32,
      tier_id::8,
      packet.contribution_score::little-32
    >>
  end
end
```

### 3. event_loot_tables.json

Static data for event-specific loot tables. Create at `apps/bezgelor_data/priv/data/event_loot_tables.json`.

### 4. Event Schema Tests

Add test file at `apps/bezgelor_db/test/schema/event_instance_test.exs` covering all event schemas.

---

## Task 1: Create Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_public_event_tables.exs`

**Step 1: Generate migration**

Run: `cd . && mix ecto.gen.migration create_public_event_tables --migrations-path apps/bezgelor_db/priv/repo/migrations`

**Step 2: Write migration content**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreatePublicEventTables do
  use Ecto.Migration

  def change do
    # Active event instances
    create table(:event_instances) do
      add :event_id, :integer, null: false
      add :zone_id, :integer, null: false
      add :instance_id, :integer, null: false, default: 1
      add :state, :string, null: false, default: "pending"
      add :current_phase, :integer, null: false, default: 0
      add :current_wave, :integer, null: false, default: 0
      add :phase_progress, :map, default: %{}
      add :participant_count, :integer, null: false, default: 0
      add :difficulty_multiplier, :float, null: false, default: 1.0
      add :started_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:event_instances, [:zone_id, :instance_id])
    create index(:event_instances, [:state])
    create index(:event_instances, [:event_id, :state])

    # Player participation
    create table(:event_participations) do
      add :event_instance_id, references(:event_instances, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :contribution_score, :integer, null: false, default: 0
      add :kills, :integer, null: false, default: 0
      add :damage_dealt, :integer, null: false, default: 0
      add :healing_done, :integer, null: false, default: 0
      add :objectives_completed, {:array, :integer}, default: []
      add :reward_tier, :string
      add :rewards_claimed, :boolean, default: false
      add :joined_at, :utc_datetime
      add :last_activity_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_participations, [:event_instance_id, :character_id])
    create index(:event_participations, [:character_id])

    # Completion history
    create table(:event_completions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :event_id, :integer, null: false
      add :completion_count, :integer, null: false, default: 1
      add :gold_count, :integer, null: false, default: 0
      add :silver_count, :integer, null: false, default: 0
      add :bronze_count, :integer, null: false, default: 0
      add :best_contribution, :integer, null: false, default: 0
      add :fastest_completion_ms, :integer
      add :last_completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_completions, [:character_id, :event_id])
    create index(:event_completions, [:character_id])

    # Event scheduling
    create table(:event_schedules) do
      add :event_id, :integer, null: false
      add :zone_id, :integer, null: false
      add :enabled, :boolean, default: true
      add :trigger_type, :string, null: false
      add :trigger_config, :map, default: %{}
      add :last_triggered_at, :utc_datetime
      add :next_trigger_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:event_schedules, [:zone_id])
    create index(:event_schedules, [:enabled, :next_trigger_at])

    # World boss spawns
    create table(:world_boss_spawns) do
      add :boss_id, :integer, null: false
      add :zone_id, :integer, null: false
      add :state, :string, null: false, default: "waiting"
      add :spawn_window_start, :utc_datetime
      add :spawn_window_end, :utc_datetime
      add :spawned_at, :utc_datetime
      add :killed_at, :utc_datetime
      add :next_spawn_after, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:world_boss_spawns, [:boss_id])
    create index(:world_boss_spawns, [:zone_id])
    create index(:world_boss_spawns, [:state])
  end
end
```

**Step 3: Run migration**

Run: `cd . && MIX_ENV=test mix ecto.migrate`
Expected: Migration completes successfully

**Step 4: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/*_create_public_event_tables.exs
git commit -m "feat(db): add public event tables migration"
```

---

## Task 2: EventInstance Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_instance.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventInstance do
  @moduledoc """
  Active public event instance.

  Tracks an in-progress event in a specific zone, including current phase,
  wave progress, objectives, and participant count.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states [:pending, :active, :completed, :failed, :cancelled]

  schema "event_instances" do
    field :event_id, :integer
    field :zone_id, :integer
    field :instance_id, :integer, default: 1
    field :state, Ecto.Enum, values: @states, default: :pending
    field :current_phase, :integer, default: 0
    field :current_wave, :integer, default: 0
    field :phase_progress, :map, default: %{}
    field :participant_count, :integer, default: 0
    field :difficulty_multiplier, :float, default: 1.0
    field :started_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :completed_at, :utc_datetime

    has_many :participations, BezgelorDb.Schema.EventParticipation

    timestamps(type: :utc_datetime)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :event_id, :zone_id, :instance_id, :state, :current_phase, :current_wave,
      :phase_progress, :participant_count, :difficulty_multiplier, :started_at, :ends_at
    ])
    |> validate_required([:event_id, :zone_id])
    |> validate_number(:current_phase, greater_than_or_equal_to: 0)
    |> validate_number(:current_wave, greater_than_or_equal_to: 0)
    |> validate_number(:participant_count, greater_than_or_equal_to: 0)
    |> validate_number(:difficulty_multiplier, greater_than: 0)
  end

  def start_changeset(instance, started_at, ends_at) do
    instance
    |> change(state: :active, started_at: started_at, ends_at: ends_at)
  end

  def progress_changeset(instance, progress) do
    instance
    |> change(phase_progress: progress)
  end

  def advance_phase_changeset(instance, new_phase, new_progress) do
    instance
    |> change(current_phase: new_phase, phase_progress: new_progress)
  end

  def advance_wave_changeset(instance, new_wave) do
    instance
    |> change(current_wave: new_wave)
  end

  def participant_changeset(instance, count) do
    instance
    |> change(participant_count: count)
  end

  def difficulty_changeset(instance, multiplier) do
    instance
    |> change(difficulty_multiplier: multiplier)
  end

  def complete_changeset(instance, completed_at) do
    instance
    |> change(state: :completed, completed_at: completed_at)
  end

  def fail_changeset(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    instance
    |> change(state: :failed, completed_at: now)
  end

  def cancel_changeset(instance) do
    instance
    |> change(state: :cancelled)
  end

  def valid_states, do: @states
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_instance.ex
git commit -m "feat(db): add EventInstance schema"
```

---

## Task 3: EventParticipation Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_participation.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventParticipation do
  @moduledoc """
  Player participation in a public event.

  Tracks contribution score, combat stats, completed objectives,
  and reward tier for each participant.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{EventInstance, Character}

  @reward_tiers [:gold, :silver, :bronze, :participation]

  schema "event_participations" do
    belongs_to :event_instance, EventInstance
    belongs_to :character, Character

    field :contribution_score, :integer, default: 0
    field :kills, :integer, default: 0
    field :damage_dealt, :integer, default: 0
    field :healing_done, :integer, default: 0
    field :objectives_completed, {:array, :integer}, default: []

    field :reward_tier, Ecto.Enum, values: @reward_tiers
    field :rewards_claimed, :boolean, default: false
    field :joined_at, :utc_datetime
    field :last_activity_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [
      :event_instance_id, :character_id, :contribution_score, :kills,
      :damage_dealt, :healing_done, :objectives_completed, :reward_tier,
      :rewards_claimed, :joined_at, :last_activity_at
    ])
    |> validate_required([:event_instance_id, :character_id])
    |> validate_number(:contribution_score, greater_than_or_equal_to: 0)
    |> validate_number(:kills, greater_than_or_equal_to: 0)
    |> validate_number(:damage_dealt, greater_than_or_equal_to: 0)
    |> validate_number(:healing_done, greater_than_or_equal_to: 0)
    |> unique_constraint([:event_instance_id, :character_id])
    |> foreign_key_constraint(:event_instance_id)
    |> foreign_key_constraint(:character_id)
  end

  def contribute_changeset(participation, points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    new_score = participation.contribution_score + points

    participation
    |> change(contribution_score: new_score, last_activity_at: now)
  end

  def kill_changeset(participation, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      kills: participation.kills + 1,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def damage_changeset(participation, damage, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      damage_dealt: participation.damage_dealt + damage,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def healing_changeset(participation, healing, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      healing_done: participation.healing_done + healing,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def complete_objective_changeset(participation, objective_index, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    objectives =
      if objective_index in participation.objectives_completed do
        participation.objectives_completed
      else
        [objective_index | participation.objectives_completed]
      end

    participation
    |> change(
      objectives_completed: objectives,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def set_tier_changeset(participation, tier) do
    participation
    |> change(reward_tier: tier)
  end

  def claim_rewards_changeset(participation) do
    participation
    |> change(rewards_claimed: true)
  end

  def valid_reward_tiers, do: @reward_tiers
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_participation.ex
git commit -m "feat(db): add EventParticipation schema"
```

---

## Task 4: EventCompletion Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_completion.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventCompletion do
  @moduledoc """
  Historical record of event completions per character.

  Tracks completion count by tier, best contribution score,
  and fastest completion time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "event_completions" do
    belongs_to :character, Character
    field :event_id, :integer

    field :completion_count, :integer, default: 1
    field :gold_count, :integer, default: 0
    field :silver_count, :integer, default: 0
    field :bronze_count, :integer, default: 0
    field :best_contribution, :integer, default: 0
    field :fastest_completion_ms, :integer
    field :last_completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [
      :character_id, :event_id, :completion_count, :gold_count, :silver_count,
      :bronze_count, :best_contribution, :fastest_completion_ms, :last_completed_at
    ])
    |> validate_required([:character_id, :event_id])
    |> validate_number(:completion_count, greater_than: 0)
    |> validate_number(:gold_count, greater_than_or_equal_to: 0)
    |> validate_number(:silver_count, greater_than_or_equal_to: 0)
    |> validate_number(:bronze_count, greater_than_or_equal_to: 0)
    |> validate_number(:best_contribution, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :event_id])
    |> foreign_key_constraint(:character_id)
  end

  def increment_changeset(completion, tier, contribution, duration_ms, completed_at) do
    tier_updates = tier_increment(tier)
    best = max(completion.best_contribution, contribution)

    fastest =
      case completion.fastest_completion_ms do
        nil -> duration_ms
        existing -> min(existing, duration_ms)
      end

    completion
    |> change(
      completion_count: completion.completion_count + 1,
      gold_count: completion.gold_count + tier_updates.gold,
      silver_count: completion.silver_count + tier_updates.silver,
      bronze_count: completion.bronze_count + tier_updates.bronze,
      best_contribution: best,
      fastest_completion_ms: fastest,
      last_completed_at: completed_at
    )
  end

  defp tier_increment(:gold), do: %{gold: 1, silver: 0, bronze: 0}
  defp tier_increment(:silver), do: %{gold: 0, silver: 1, bronze: 0}
  defp tier_increment(:bronze), do: %{gold: 0, silver: 0, bronze: 1}
  defp tier_increment(_), do: %{gold: 0, silver: 0, bronze: 0}
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_completion.ex
git commit -m "feat(db): add EventCompletion schema"
```

---

## Task 5: EventSchedule Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_schedule.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventSchedule do
  @moduledoc """
  Event scheduling configuration.

  Defines when and how events are triggered: by timer, random window,
  player count, or chain from another event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @trigger_types [:timer, :random_window, :player_count, :chain, :manual]

  schema "event_schedules" do
    field :event_id, :integer
    field :zone_id, :integer
    field :enabled, :boolean, default: true

    field :trigger_type, Ecto.Enum, values: @trigger_types
    field :trigger_config, :map, default: %{}
    # timer: %{"interval_hours" => 2, "offset_minutes" => 30}
    # random_window: %{"start_hour" => 18, "end_hour" => 22, "min_gap_hours" => 4}
    # player_count: %{"min_players" => 10, "check_interval_ms" => 60000}
    # chain: %{"after_event_id" => 1001, "delay_ms" => 30000}

    field :last_triggered_at, :utc_datetime
    field :next_trigger_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :event_id, :zone_id, :enabled, :trigger_type, :trigger_config,
      :last_triggered_at, :next_trigger_at
    ])
    |> validate_required([:event_id, :zone_id, :trigger_type])
  end

  def enable_changeset(schedule) do
    schedule
    |> change(enabled: true)
  end

  def disable_changeset(schedule) do
    schedule
    |> change(enabled: false)
  end

  def trigger_changeset(schedule, triggered_at, next_trigger_at) do
    schedule
    |> change(last_triggered_at: triggered_at, next_trigger_at: next_trigger_at)
  end

  def update_next_trigger_changeset(schedule, next_trigger_at) do
    schedule
    |> change(next_trigger_at: next_trigger_at)
  end

  def valid_trigger_types, do: @trigger_types
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_schedule.ex
git commit -m "feat(db): add EventSchedule schema"
```

---

## Task 6: WorldBossSpawn Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/world_boss_spawn.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.WorldBossSpawn do
  @moduledoc """
  World boss spawn tracking.

  Manages spawn windows, current state, and cooldowns for world bosses.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states [:waiting, :spawned, :engaged, :killed]

  schema "world_boss_spawns" do
    field :boss_id, :integer
    field :zone_id, :integer

    field :state, Ecto.Enum, values: @states, default: :waiting
    field :spawn_window_start, :utc_datetime
    field :spawn_window_end, :utc_datetime
    field :spawned_at, :utc_datetime
    field :killed_at, :utc_datetime
    field :next_spawn_after, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(spawn, attrs) do
    spawn
    |> cast(attrs, [
      :boss_id, :zone_id, :state, :spawn_window_start, :spawn_window_end,
      :spawned_at, :killed_at, :next_spawn_after
    ])
    |> validate_required([:boss_id, :zone_id])
    |> unique_constraint([:boss_id])
  end

  def set_window_changeset(spawn, window_start, window_end) do
    spawn
    |> change(
      state: :waiting,
      spawn_window_start: window_start,
      spawn_window_end: window_end,
      spawned_at: nil,
      killed_at: nil
    )
  end

  def spawn_changeset(spawn) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    spawn
    |> change(state: :spawned, spawned_at: now)
  end

  def engage_changeset(spawn) do
    spawn
    |> change(state: :engaged)
  end

  def kill_changeset(spawn, next_spawn_after) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    spawn
    |> change(state: :killed, killed_at: now, next_spawn_after: next_spawn_after)
  end

  def reset_changeset(spawn) do
    spawn
    |> change(
      state: :waiting,
      spawn_window_start: nil,
      spawn_window_end: nil,
      spawned_at: nil,
      killed_at: nil
    )
  end

  def valid_states, do: @states
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/world_boss_spawn.ex
git commit -m "feat(db): add WorldBossSpawn schema"
```

---

## Task 7: PublicEvents Context - Core

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/public_events.ex`
- Create: `apps/bezgelor_db/test/public_events_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.PublicEventsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, PublicEvents, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "eventer#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    {:ok, character} = Characters.create_character(account.id, %{
      name: "EventHero#{System.unique_integer([:positive])}",
      sex: 0,
      race: 0,
      class: 0,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1
    })

    %{character: character}
  end

  describe "create_event_instance/3" do
    test "creates a new event instance" do
      assert {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      assert instance.event_id == 1
      assert instance.zone_id == 100
      assert instance.instance_id == 1
      assert instance.state == :pending
      assert instance.current_phase == 0
    end
  end

  describe "start_event/2" do
    test "starts a pending event" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)

      assert {:ok, started} = PublicEvents.start_event(instance.id, 300_000)
      assert started.state == :active
      assert started.started_at != nil
      assert started.ends_at != nil
    end

    test "cannot start non-pending event" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:error, :invalid_state} = PublicEvents.start_event(instance.id, 300_000)
    end
  end

  describe "get_active_events/2" do
    test "returns only active events in zone" do
      {:ok, pending} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, active_instance} = PublicEvents.create_event_instance(2, 100, 1)
      {:ok, _} = PublicEvents.start_event(active_instance.id, 300_000)
      {:ok, other_zone} = PublicEvents.create_event_instance(3, 200, 1)
      {:ok, _} = PublicEvents.start_event(other_zone.id, 300_000)

      active = PublicEvents.get_active_events(100, 1)
      assert length(active) == 1
      assert hd(active).event_id == 2
    end
  end

  describe "complete_event/1" do
    test "marks active event as completed" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, completed} = PublicEvents.complete_event(instance.id)
      assert completed.state == :completed
      assert completed.completed_at != nil
    end
  end

  describe "fail_event/1" do
    test "marks active event as failed" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, failed} = PublicEvents.fail_event(instance.id)
      assert failed.state == :failed
    end
  end

  describe "advance_phase/3" do
    test "advances to next phase" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, advanced} = PublicEvents.advance_phase(instance.id, 1, %{"objectives" => []})
      assert advanced.current_phase == 1
    end
  end

  describe "update_progress/2" do
    test "updates phase progress" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      progress = %{"objectives" => [%{"index" => 0, "current" => 5, "target" => 10}]}
      assert {:ok, updated} = PublicEvents.update_progress(instance.id, progress)
      assert updated.phase_progress == progress
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: FAIL with "module BezgelorDb.PublicEvents is not available"

**Step 3: Write implementation**

```elixir
defmodule BezgelorDb.PublicEvents do
  @moduledoc """
  Public events management context.

  Handles event instances, participation tracking, contributions,
  scheduling, and completion history.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{EventInstance, EventParticipation, EventCompletion, EventSchedule, WorldBossSpawn}

  # ============================================================================
  # Event Instance Management
  # ============================================================================

  @doc "Get an event instance by ID."
  def get_event_instance(instance_id) do
    Repo.get(EventInstance, instance_id)
  end

  @doc "Get an event instance with participations preloaded."
  def get_event_instance_with_participations(instance_id) do
    EventInstance
    |> where([e], e.id == ^instance_id)
    |> preload(:participations)
    |> Repo.one()
  end

  @doc "Get all active events in a zone."
  def get_active_events(zone_id, instance_id \\ 1) do
    EventInstance
    |> where([e], e.zone_id == ^zone_id and e.instance_id == ^instance_id)
    |> where([e], e.state == :active)
    |> order_by([e], asc: e.started_at)
    |> Repo.all()
  end

  @doc "Get all events in a zone (any state)."
  def get_zone_events(zone_id, instance_id \\ 1) do
    EventInstance
    |> where([e], e.zone_id == ^zone_id and e.instance_id == ^instance_id)
    |> where([e], e.state in [:pending, :active])
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Create a new event instance."
  def create_event_instance(event_id, zone_id, instance_id \\ 1) do
    %EventInstance{}
    |> EventInstance.changeset(%{
      event_id: event_id,
      zone_id: zone_id,
      instance_id: instance_id
    })
    |> Repo.insert()
  end

  @doc "Start a pending event."
  def start_event(instance_id, duration_ms) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :pending} = instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ends_at = DateTime.add(now, duration_ms, :millisecond)

        instance
        |> EventInstance.start_changeset(now, ends_at)
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Complete an event successfully."
  def complete_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :active} = instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        instance
        |> EventInstance.complete_changeset(now)
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Fail an event."
  def fail_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :active} = instance ->
        instance
        |> EventInstance.fail_changeset()
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Cancel an event."
  def cancel_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: state} = instance when state in [:pending, :active] ->
        instance
        |> EventInstance.cancel_changeset()
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Advance to next phase."
  def advance_phase(instance_id, new_phase, initial_progress) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.advance_phase_changeset(new_phase, initial_progress)
        |> Repo.update()
    end
  end

  @doc "Advance to next wave."
  def advance_wave(instance_id, new_wave) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.advance_wave_changeset(new_wave)
        |> Repo.update()
    end
  end

  @doc "Update phase progress."
  def update_progress(instance_id, progress) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.progress_changeset(progress)
        |> Repo.update()
    end
  end

  @doc "Update participant count."
  def update_participant_count(instance_id) do
    count =
      EventParticipation
      |> where([p], p.event_instance_id == ^instance_id)
      |> Repo.aggregate(:count)

    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.participant_changeset(count)
        |> Repo.update()
    end
  end

  @doc "Update difficulty multiplier based on participant count."
  def update_difficulty(instance_id, participant_count) do
    multiplier = calculate_difficulty_multiplier(participant_count)

    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.difficulty_changeset(multiplier)
        |> Repo.update()
    end
  end

  defp calculate_difficulty_multiplier(count) when count <= 10, do: 1.0
  defp calculate_difficulty_multiplier(count) when count <= 25, do: 1.5
  defp calculate_difficulty_multiplier(count) when count <= 50, do: 2.0
  defp calculate_difficulty_multiplier(_count), do: 2.5
end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/public_events.ex apps/bezgelor_db/test/public_events_test.exs
git commit -m "feat(db): add PublicEvents context - core functions"
```

---

## Task 8: PublicEvents Context - Participation

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/public_events.ex`
- Modify: `apps/bezgelor_db/test/public_events_test.exs`

**Step 1: Add participation tests**

Add to `public_events_test.exs`:

```elixir
  describe "join_event/2" do
    test "player joins an active event", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, participation} = PublicEvents.join_event(instance.id, char.id)
      assert participation.character_id == char.id
      assert participation.contribution_score == 0
      assert participation.joined_at != nil
    end

    test "cannot join same event twice", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:error, :already_joined} = PublicEvents.join_event(instance.id, char.id)
    end
  end

  describe "add_contribution/3" do
    test "adds contribution points", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.add_contribution(instance.id, char.id, 50)
      assert updated.contribution_score == 50

      assert {:ok, again} = PublicEvents.add_contribution(instance.id, char.id, 30)
      assert again.contribution_score == 80
    end

    test "auto-joins player if not participating", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, participation} = PublicEvents.add_contribution(instance.id, char.id, 50)
      assert participation.contribution_score == 50
    end
  end

  describe "record_kill/3" do
    test "records kill and adds contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.record_kill(instance.id, char.id, 10)
      assert updated.kills == 1
      assert updated.contribution_score == 10
    end
  end

  describe "record_damage/3" do
    test "records damage dealt", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.record_damage(instance.id, char.id, 1000, 5)
      assert updated.damage_dealt == 1000
      assert updated.contribution_score == 5
    end
  end

  describe "calculate_reward_tiers/1" do
    test "assigns tiers based on contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 500)

      assert {:ok, participations} = PublicEvents.calculate_reward_tiers(instance.id)
      assert length(participations) == 1
      assert hd(participations).reward_tier == :gold
    end
  end

  describe "get_participations/1" do
    test "returns participations ordered by contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 100)

      participations = PublicEvents.get_participations(instance.id)
      assert length(participations) == 1
      assert hd(participations).contribution_score == 100
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: FAIL with undefined function errors

**Step 3: Add participation functions to context**

Add to `public_events.ex`:

```elixir
  # ============================================================================
  # Participation Management
  # ============================================================================

  @doc "Get participation record."
  def get_participation(instance_id, character_id) do
    Repo.get_by(EventParticipation, event_instance_id: instance_id, character_id: character_id)
  end

  @doc "Get all participations for an event, ordered by contribution."
  def get_participations(instance_id) do
    EventParticipation
    |> where([p], p.event_instance_id == ^instance_id)
    |> order_by([p], desc: p.contribution_score)
    |> Repo.all()
  end

  @doc "Get top N contributors."
  def get_top_contributors(instance_id, limit \\ 10) do
    EventParticipation
    |> where([p], p.event_instance_id == ^instance_id)
    |> order_by([p], desc: p.contribution_score)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Join an event."
  def join_event(instance_id, character_id) do
    if get_participation(instance_id, character_id) do
      {:error, :already_joined}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        %EventParticipation{}
        |> EventParticipation.changeset(%{
          event_instance_id: instance_id,
          character_id: character_id,
          joined_at: now,
          last_activity_at: now
        })
        |> Repo.insert()

      case result do
        {:ok, participation} ->
          update_participant_count(instance_id)
          {:ok, participation}

        error ->
          error
      end
    end
  end

  @doc "Add contribution points. Auto-joins if not participating."
  def add_contribution(instance_id, character_id, points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.contribute_changeset(points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record a kill."
  def record_kill(instance_id, character_id, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.kill_changeset(contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record damage dealt."
  def record_damage(instance_id, character_id, damage, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.damage_changeset(damage, contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record healing done."
  def record_healing(instance_id, character_id, healing, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.healing_changeset(healing, contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Complete an objective for a participant."
  def complete_objective(instance_id, character_id, objective_index, contribution_points) do
    case get_participation(instance_id, character_id) do
      nil ->
        {:error, :not_participating}

      participation ->
        participation
        |> EventParticipation.complete_objective_changeset(objective_index, contribution_points)
        |> Repo.update()
    end
  end

  @doc "Calculate and assign reward tiers for all participants."
  def calculate_reward_tiers(instance_id) do
    participations = get_participations(instance_id)
    total = length(participations)

    if total == 0 do
      {:ok, []}
    else
      # Calculate tier thresholds
      gold_threshold = max(1, ceil(total * 0.1))
      silver_threshold = max(1, ceil(total * 0.25))
      bronze_threshold = max(1, ceil(total * 0.5))

      updated =
        participations
        |> Enum.with_index(1)
        |> Enum.map(fn {p, rank} ->
          tier = determine_tier(rank, p.contribution_score, gold_threshold, silver_threshold, bronze_threshold)

          {:ok, updated} =
            p
            |> EventParticipation.set_tier_changeset(tier)
            |> Repo.update()

          updated
        end)

      {:ok, updated}
    end
  end

  defp determine_tier(rank, score, gold_t, silver_t, bronze_t) do
    cond do
      rank <= gold_t or score >= 500 -> :gold
      rank <= silver_t or score >= 300 -> :silver
      rank <= bronze_t or score >= 100 -> :bronze
      true -> :participation
    end
  end

  @doc "Claim rewards for a participant."
  def claim_rewards(instance_id, character_id) do
    case get_participation(instance_id, character_id) do
      nil ->
        {:error, :not_participating}

      %{rewards_claimed: true} ->
        {:error, :already_claimed}

      participation ->
        participation
        |> EventParticipation.claim_rewards_changeset()
        |> Repo.update()
    end
  end

  defp get_or_create_participation(instance_id, character_id) do
    case get_participation(instance_id, character_id) do
      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        result =
          %EventParticipation{}
          |> EventParticipation.changeset(%{
            event_instance_id: instance_id,
            character_id: character_id,
            joined_at: now,
            last_activity_at: now
          })
          |> Repo.insert()

        case result do
          {:ok, participation} ->
            update_participant_count(instance_id)
            {:ok, participation}

          error ->
            error
        end

      participation ->
        {:ok, participation}
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/public_events.ex apps/bezgelor_db/test/public_events_test.exs
git commit -m "feat(db): add PublicEvents participation functions"
```

---

## Task 9: PublicEvents Context - Scheduling & Completion History

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/public_events.ex`
- Modify: `apps/bezgelor_db/test/public_events_test.exs`

**Step 1: Add scheduling and completion tests**

Add to `public_events_test.exs`:

```elixir
  describe "record_completion/4" do
    test "records first completion", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 500)

      assert {:ok, completion} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)
      assert completion.completion_count == 1
      assert completion.gold_count == 1
      assert completion.best_contribution == 500
    end

    test "increments completion count", %{character: char} do
      {:ok, _} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)
      {:ok, completion} = PublicEvents.record_completion(char.id, 1, :silver, 300, 45000)

      assert completion.completion_count == 2
      assert completion.gold_count == 1
      assert completion.silver_count == 1
      assert completion.best_contribution == 500
      assert completion.fastest_completion_ms == 45000
    end
  end

  describe "get_completion_history/2" do
    test "returns completion record", %{character: char} do
      {:ok, _} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)

      history = PublicEvents.get_completion_history(char.id, 1)
      assert history.completion_count == 1
      assert history.gold_count == 1
    end

    test "returns nil for no completions", %{character: char} do
      assert PublicEvents.get_completion_history(char.id, 999) == nil
    end
  end

  describe "create_schedule/4" do
    test "creates a timer schedule" do
      config = %{"interval_hours" => 2, "offset_minutes" => 30}
      assert {:ok, schedule} = PublicEvents.create_schedule(1, 100, :timer, config)
      assert schedule.trigger_type == :timer
      assert schedule.enabled == true
    end
  end

  describe "get_due_schedules/0" do
    test "returns schedules past their trigger time" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      config = %{"interval_hours" => 2}

      {:ok, _} = PublicEvents.create_schedule(1, 100, :timer, config)
      |> then(fn {:ok, s} -> PublicEvents.set_next_trigger(s.id, past) end)

      schedules = PublicEvents.get_due_schedules()
      assert length(schedules) >= 1
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: FAIL with undefined function errors

**Step 3: Add scheduling and completion functions**

Add to `public_events.ex`:

```elixir
  # ============================================================================
  # Completion History
  # ============================================================================

  @doc "Get completion history for a character and event."
  def get_completion_history(character_id, event_id) do
    Repo.get_by(EventCompletion, character_id: character_id, event_id: event_id)
  end

  @doc "Get all completions for a character."
  def get_all_completions(character_id) do
    EventCompletion
    |> where([c], c.character_id == ^character_id)
    |> order_by([c], desc: c.last_completed_at)
    |> Repo.all()
  end

  @doc "Record a completion."
  def record_completion(character_id, event_id, tier, contribution, duration_ms) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_completion_history(character_id, event_id) do
      nil ->
        tier_counts = tier_to_counts(tier)

        %EventCompletion{}
        |> EventCompletion.changeset(%{
          character_id: character_id,
          event_id: event_id,
          gold_count: tier_counts.gold,
          silver_count: tier_counts.silver,
          bronze_count: tier_counts.bronze,
          best_contribution: contribution,
          fastest_completion_ms: duration_ms,
          last_completed_at: now
        })
        |> Repo.insert()

      existing ->
        existing
        |> EventCompletion.increment_changeset(tier, contribution, duration_ms, now)
        |> Repo.update()
    end
  end

  defp tier_to_counts(:gold), do: %{gold: 1, silver: 0, bronze: 0}
  defp tier_to_counts(:silver), do: %{gold: 0, silver: 1, bronze: 0}
  defp tier_to_counts(:bronze), do: %{gold: 0, silver: 0, bronze: 1}
  defp tier_to_counts(_), do: %{gold: 0, silver: 0, bronze: 0}

  # ============================================================================
  # Scheduling
  # ============================================================================

  @doc "Get a schedule by ID."
  def get_schedule(schedule_id) do
    Repo.get(EventSchedule, schedule_id)
  end

  @doc "Get all schedules for a zone."
  def get_zone_schedules(zone_id) do
    EventSchedule
    |> where([s], s.zone_id == ^zone_id and s.enabled == true)
    |> Repo.all()
  end

  @doc "Get all enabled schedules that are due to trigger."
  def get_due_schedules do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    EventSchedule
    |> where([s], s.enabled == true)
    |> where([s], is_nil(s.next_trigger_at) or s.next_trigger_at <= ^now)
    |> Repo.all()
  end

  @doc "Create a new schedule."
  def create_schedule(event_id, zone_id, trigger_type, config) do
    %EventSchedule{}
    |> EventSchedule.changeset(%{
      event_id: event_id,
      zone_id: zone_id,
      trigger_type: trigger_type,
      trigger_config: config
    })
    |> Repo.insert()
  end

  @doc "Set the next trigger time."
  def set_next_trigger(schedule_id, next_trigger_at) do
    case get_schedule(schedule_id) do
      nil ->
        {:error, :not_found}

      schedule ->
        schedule
        |> EventSchedule.update_next_trigger_changeset(next_trigger_at)
        |> Repo.update()
    end
  end

  @doc "Mark a schedule as triggered."
  def mark_triggered(schedule_id, next_trigger_at) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_schedule(schedule_id) do
      nil ->
        {:error, :not_found}

      schedule ->
        schedule
        |> EventSchedule.trigger_changeset(now, next_trigger_at)
        |> Repo.update()
    end
  end

  @doc "Enable a schedule."
  def enable_schedule(schedule_id) do
    case get_schedule(schedule_id) do
      nil -> {:error, :not_found}
      schedule ->
        schedule
        |> EventSchedule.enable_changeset()
        |> Repo.update()
    end
  end

  @doc "Disable a schedule."
  def disable_schedule(schedule_id) do
    case get_schedule(schedule_id) do
      nil -> {:error, :not_found}
      schedule ->
        schedule
        |> EventSchedule.disable_changeset()
        |> Repo.update()
    end
  end

  # ============================================================================
  # World Boss Spawns
  # ============================================================================

  @doc "Get world boss spawn record."
  def get_boss_spawn(boss_id) do
    Repo.get_by(WorldBossSpawn, boss_id: boss_id)
  end

  @doc "Get all spawned bosses in a zone."
  def get_spawned_bosses(zone_id) do
    WorldBossSpawn
    |> where([b], b.zone_id == ^zone_id)
    |> where([b], b.state in [:spawned, :engaged])
    |> Repo.all()
  end

  @doc "Get all bosses waiting to spawn."
  def get_waiting_bosses do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    WorldBossSpawn
    |> where([b], b.state == :waiting)
    |> where([b], b.spawn_window_start <= ^now and b.spawn_window_end >= ^now)
    |> Repo.all()
  end

  @doc "Create or update boss spawn record."
  def create_boss_spawn(boss_id, zone_id) do
    case get_boss_spawn(boss_id) do
      nil ->
        %WorldBossSpawn{}
        |> WorldBossSpawn.changeset(%{boss_id: boss_id, zone_id: zone_id})
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  @doc "Set spawn window for a boss."
  def set_boss_spawn_window(boss_id, window_start, window_end) do
    case get_boss_spawn(boss_id) do
      nil ->
        {:error, :not_found}

      spawn ->
        spawn
        |> WorldBossSpawn.set_window_changeset(window_start, window_end)
        |> Repo.update()
    end
  end

  @doc "Mark boss as spawned."
  def spawn_boss(boss_id) do
    case get_boss_spawn(boss_id) do
      nil ->
        {:error, :not_found}

      spawn ->
        spawn
        |> WorldBossSpawn.spawn_changeset()
        |> Repo.update()
    end
  end

  @doc "Mark boss as engaged in combat."
  def engage_boss(boss_id) do
    case get_boss_spawn(boss_id) do
      nil ->
        {:error, :not_found}

      spawn ->
        spawn
        |> WorldBossSpawn.engage_changeset()
        |> Repo.update()
    end
  end

  @doc "Mark boss as killed."
  def kill_boss(boss_id, cooldown_hours) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    next_spawn = DateTime.add(now, cooldown_hours * 3600, :second)

    case get_boss_spawn(boss_id) do
      nil ->
        {:error, :not_found}

      spawn ->
        spawn
        |> WorldBossSpawn.kill_changeset(next_spawn)
        |> Repo.update()
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/public_events.ex apps/bezgelor_db/test/public_events_test.exs
git commit -m "feat(db): add PublicEvents scheduling and completion history"
```

---

## Task 10: Static Data Files

**Files:**
- Create: `apps/bezgelor_data/priv/data/public_events.json`
- Create: `apps/bezgelor_data/priv/data/world_bosses.json`
- Create: `apps/bezgelor_data/priv/data/event_spawn_points.json`

**Step 1: Create public_events.json**

```json
[
  {
    "id": 1001,
    "name": "Strain Invasion",
    "type": "invasion",
    "zone_id": 100,
    "duration_ms": 600000,
    "phases": [
      {
        "index": 0,
        "objectives": [
          {"index": 0, "type": "kill", "target": 30, "creature_ids": [1001, 1002], "contribution_per_unit": 10}
        ],
        "duration_ms": 180000
      },
      {
        "index": 1,
        "objectives": [
          {"index": 0, "type": "kill", "target": 50, "creature_ids": [1001, 1002, 1003], "contribution_per_unit": 10},
          {"index": 1, "type": "defend", "target": 1, "object_ids": [2001], "duration_ms": 60000, "contribution_per_unit": 50}
        ],
        "duration_ms": 240000
      },
      {
        "index": 2,
        "objectives": [
          {"index": 0, "type": "kill_boss", "target": 1, "boss_id": 1004, "contribution_per_unit": 100}
        ],
        "duration_ms": 180000
      }
    ],
    "rewards": {
      "xp": 500,
      "gold": 100,
      "currency": {"glory": 50},
      "loot_table_id": 9001,
      "reputation": {"faction_id": 100, "amount": 250},
      "achievement_id": 8001
    },
    "spawn_points": "invasion_north"
  },
  {
    "id": 1002,
    "name": "Resource Collection",
    "type": "collection",
    "zone_id": 100,
    "duration_ms": 300000,
    "phases": [
      {
        "index": 0,
        "objectives": [
          {"index": 0, "type": "collect", "target": 100, "item_id": 3001, "contribution_per_unit": 5}
        ],
        "duration_ms": 300000
      }
    ],
    "rewards": {
      "xp": 300,
      "gold": 50,
      "loot_table_id": 9002
    },
    "spawn_points": null
  },
  {
    "id": 1003,
    "name": "Territory Control",
    "type": "territory",
    "zone_id": 200,
    "duration_ms": 600000,
    "control_points": [
      {"id": "alpha", "name": "Northern Outpost", "position": [100.0, 200.0, 50.0], "capture_radius": 30.0, "capture_time_ms": 15000},
      {"id": "beta", "name": "Central Tower", "position": [150.0, 150.0, 55.0], "capture_radius": 25.0, "capture_time_ms": 20000},
      {"id": "gamma", "name": "Southern Gate", "position": [200.0, 100.0, 48.0], "capture_radius": 35.0, "capture_time_ms": 10000}
    ],
    "victory_condition": "hold_majority",
    "hold_time_required_ms": 120000,
    "rewards": {
      "xp": 400,
      "gold": 75,
      "currency": {"glory": 75}
    }
  }
]
```

**Step 2: Create world_bosses.json**

```json
[
  {
    "id": 5001,
    "name": "Metal Maw",
    "creature_template_id": 10001,
    "zone_id": 100,
    "spawn_position": [1234.5, 567.8, 90.0],
    "spawn_window": {"start_hour": 18, "end_hour": 22},
    "spawn_cooldown_hours": 24,
    "despawn_timer_ms": 1800000,
    "phases": [
      {
        "health_threshold": 100,
        "abilities": ["ground_slam", "cleave"],
        "add_spawns": []
      },
      {
        "health_threshold": 60,
        "abilities": ["ground_slam", "cleave", "enrage"],
        "add_spawns": [{"creature_id": 1005, "count": 4}]
      },
      {
        "health_threshold": 30,
        "abilities": ["ground_slam", "cleave", "enrage", "berserk"],
        "add_spawns": [{"creature_id": 1005, "count": 8}]
      }
    ],
    "enrage_timer_ms": 600000,
    "loot_table_id": 9101,
    "currency_reward": {"omnibits": 50, "glory": 100},
    "achievement_id": 8101,
    "title_id": 7001
  },
  {
    "id": 5002,
    "name": "Scorchwing",
    "creature_template_id": 10002,
    "zone_id": 200,
    "spawn_position": [500.0, 800.0, 120.0],
    "spawn_window": {"start_hour": 12, "end_hour": 16},
    "spawn_cooldown_hours": 48,
    "despawn_timer_ms": 2400000,
    "phases": [
      {
        "health_threshold": 100,
        "abilities": ["fire_breath", "wing_buffet"],
        "add_spawns": []
      },
      {
        "health_threshold": 50,
        "abilities": ["fire_breath", "wing_buffet", "meteor_swarm"],
        "add_spawns": [{"creature_id": 1010, "count": 6}]
      }
    ],
    "enrage_timer_ms": 900000,
    "loot_table_id": 9102,
    "currency_reward": {"omnibits": 75, "glory": 150},
    "achievement_id": 8102,
    "title_id": 7002
  }
]
```

**Step 3: Create event_spawn_points.json**

```json
[
  {
    "zone_id": 100,
    "spawn_point_groups": {
      "invasion_north": [
        {"position": [1100.0, 1500.0, 50.0], "rotation": 180},
        {"position": [1150.0, 1480.0, 52.0], "rotation": 180},
        {"position": [1050.0, 1520.0, 49.0], "rotation": 180}
      ],
      "invasion_south": [
        {"position": [1100.0, 900.0, 48.0], "rotation": 0},
        {"position": [1080.0, 920.0, 49.0], "rotation": 0}
      ],
      "invasion_center": [
        {"position": [1100.0, 1200.0, 55.0], "rotation": 0}
      ]
    }
  },
  {
    "zone_id": 200,
    "spawn_point_groups": {
      "assault_west": [
        {"position": [200.0, 500.0, 30.0], "rotation": 90},
        {"position": [180.0, 520.0, 32.0], "rotation": 90}
      ],
      "assault_east": [
        {"position": [800.0, 500.0, 35.0], "rotation": 270}
      ]
    }
  }
]
```

**Step 4: Commit**

```bash
git add apps/bezgelor_data/priv/data/public_events.json \
        apps/bezgelor_data/priv/data/world_bosses.json \
        apps/bezgelor_data/priv/data/event_spawn_points.json
git commit -m "feat(data): add public event static data files"
```

---

## Task 11: ETS Integration

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`
- Modify: `apps/bezgelor_data/lib/bezgelor_data.ex`

**Step 1: Add tables to Store**

In `store.ex`, add to the `@tables` list:

```elixir
@tables [
  # ... existing tables ...
  :public_events,
  :world_bosses,
  :event_spawn_points
]
```

**Step 2: Add load functions**

Add to the `load_all/0` function or create specific loaders:

```elixir
defp load_public_events do
  load_json_file("public_events.json", :public_events)
end

defp load_world_bosses do
  load_json_file("world_bosses.json", :world_bosses)
end

defp load_event_spawn_points do
  load_json_file("event_spawn_points.json", :event_spawn_points)
end
```

**Step 3: Add convenience functions to BezgelorData**

Add to `lib/bezgelor_data.ex`:

```elixir
@doc "Get a public event definition by ID."
def get_public_event(event_id) do
  Store.get(:public_events, event_id)
end

@doc "Get all public events for a zone."
def get_zone_events(zone_id) do
  Store.list(:public_events)
  |> Enum.filter(fn {_id, event} -> event["zone_id"] == zone_id end)
  |> Enum.map(fn {_id, event} -> event end)
end

@doc "Get a world boss definition by ID."
def get_world_boss(boss_id) do
  Store.get(:world_bosses, boss_id)
end

@doc "Get all world bosses for a zone."
def get_zone_world_bosses(zone_id) do
  Store.list(:world_bosses)
  |> Enum.filter(fn {_id, boss} -> boss["zone_id"] == zone_id end)
  |> Enum.map(fn {_id, boss} -> boss end)
end

@doc "Get spawn points for a zone."
def get_event_spawn_points(zone_id) do
  Store.get(:event_spawn_points, zone_id)
end

@doc "Get specific spawn point group."
def get_spawn_point_group(zone_id, group_name) do
  case get_event_spawn_points(zone_id) do
    nil -> []
    data -> get_in(data, ["spawn_point_groups", group_name]) || []
  end
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_data/lib/bezgelor_data/store.ex apps/bezgelor_data/lib/bezgelor_data.ex
git commit -m "feat(data): add public event ETS integration"
```

---

## Task 12: Server Packets - Events

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_start.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_update.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_complete.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_phase.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_contribution_update.ex`

**Step 1: Create ServerEventStart**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventStart do
  @moduledoc """
  Notify client that a public event has started.

  ## Wire Format
  instance_id     : uint32
  event_id        : uint32
  event_type      : uint8
  phase           : uint8
  duration_ms     : uint32
  objective_count : uint8
  objectives      : [Objective] * count

  Objective:
    index   : uint8
    type    : uint8
    target  : uint32
    current : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :event_id, :event_type, :phase, :duration_ms, objectives: []]

  @impl true
  def opcode, do: 0x0A01

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint32(packet.event_id)
      |> PacketWriter.write_byte(event_type_to_int(packet.event_type))
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_uint32(packet.duration_ms)
      |> PacketWriter.write_byte(length(packet.objectives))

    writer =
      Enum.reduce(packet.objectives, writer, fn obj, w ->
        w
        |> PacketWriter.write_byte(obj.index)
        |> PacketWriter.write_byte(objective_type_to_int(obj.type))
        |> PacketWriter.write_uint32(obj.target)
        |> PacketWriter.write_uint32(obj.current)
      end)

    {:ok, writer}
  end

  defp event_type_to_int(:invasion), do: 0
  defp event_type_to_int(:collection), do: 1
  defp event_type_to_int(:territory), do: 2
  defp event_type_to_int(:defense), do: 3
  defp event_type_to_int(:escort), do: 4
  defp event_type_to_int(:world_boss), do: 5
  defp event_type_to_int(_), do: 0

  defp objective_type_to_int(:kill), do: 0
  defp objective_type_to_int(:kill_boss), do: 1
  defp objective_type_to_int(:collect), do: 2
  defp objective_type_to_int(:interact), do: 3
  defp objective_type_to_int(:defend), do: 4
  defp objective_type_to_int(:escort), do: 5
  defp objective_type_to_int(:survive), do: 6
  defp objective_type_to_int(:territory), do: 7
  defp objective_type_to_int(:damage), do: 8
  defp objective_type_to_int(_), do: 0
end
```

**Step 2: Create ServerEventUpdate**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventUpdate do
  @moduledoc """
  Update event objective progress.

  ## Wire Format
  instance_id     : uint32
  objective_index : uint8
  current         : uint32
  target          : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :objective_index, :current, :target]

  @impl true
  def opcode, do: 0x0A02

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(packet.objective_index)
      |> PacketWriter.write_uint32(packet.current)
      |> PacketWriter.write_uint32(packet.target)

    {:ok, writer}
  end
end
```

**Step 3: Create ServerEventComplete**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventComplete do
  @moduledoc """
  Notify client that event has completed.

  ## Wire Format
  instance_id   : uint32
  event_id      : uint32
  success       : uint8 (0=fail, 1=success)
  reward_tier   : uint8 (0=participation, 1=bronze, 2=silver, 3=gold)
  contribution  : uint32
  reward_xp     : uint32
  reward_gold   : uint32
  reward_count  : uint8
  rewards       : [Reward] * count

  Reward:
    item_id  : uint32
    quantity : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :event_id, :success, :reward_tier, :contribution, :reward_xp, :reward_gold, rewards: []]

  @impl true
  def opcode, do: 0x0A03

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint32(packet.event_id)
      |> PacketWriter.write_byte(if(packet.success, do: 1, else: 0))
      |> PacketWriter.write_byte(tier_to_int(packet.reward_tier))
      |> PacketWriter.write_uint32(packet.contribution)
      |> PacketWriter.write_uint32(packet.reward_xp)
      |> PacketWriter.write_uint32(packet.reward_gold)
      |> PacketWriter.write_byte(length(packet.rewards))

    writer =
      Enum.reduce(packet.rewards, writer, fn reward, w ->
        w
        |> PacketWriter.write_uint32(reward.item_id)
        |> PacketWriter.write_uint16(reward.quantity)
      end)

    {:ok, writer}
  end

  defp tier_to_int(:participation), do: 0
  defp tier_to_int(:bronze), do: 1
  defp tier_to_int(:silver), do: 2
  defp tier_to_int(:gold), do: 3
  defp tier_to_int(_), do: 0
end
```

**Step 4: Create ServerEventPhase**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventPhase do
  @moduledoc """
  Notify client of phase change.

  ## Wire Format
  instance_id     : uint32
  phase           : uint8
  objective_count : uint8
  objectives      : [Objective] * count
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :phase, objectives: []]

  @impl true
  def opcode, do: 0x0A04

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_byte(length(packet.objectives))

    writer =
      Enum.reduce(packet.objectives, writer, fn obj, w ->
        w
        |> PacketWriter.write_byte(obj.index)
        |> PacketWriter.write_byte(objective_type_to_int(obj.type))
        |> PacketWriter.write_uint32(obj.target)
        |> PacketWriter.write_uint32(obj.current)
      end)

    {:ok, writer}
  end

  defp objective_type_to_int(:kill), do: 0
  defp objective_type_to_int(:kill_boss), do: 1
  defp objective_type_to_int(:collect), do: 2
  defp objective_type_to_int(:interact), do: 3
  defp objective_type_to_int(:defend), do: 4
  defp objective_type_to_int(:escort), do: 5
  defp objective_type_to_int(:survive), do: 6
  defp objective_type_to_int(:territory), do: 7
  defp objective_type_to_int(:damage), do: 8
  defp objective_type_to_int(_), do: 0
end
```

**Step 5: Create ServerEventList**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventList do
  @moduledoc """
  List of active events in zone.

  ## Wire Format
  event_count : uint8
  events      : [Event] * count

  Event:
    instance_id : uint32
    event_id    : uint32
    event_type  : uint8
    phase       : uint8
    time_remaining_ms : uint32
    participant_count : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct events: []

  @impl true
  def opcode, do: 0x0A05

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_byte(writer, length(packet.events))

    writer =
      Enum.reduce(packet.events, writer, fn event, w ->
        w
        |> PacketWriter.write_uint32(event.instance_id)
        |> PacketWriter.write_uint32(event.event_id)
        |> PacketWriter.write_byte(event_type_to_int(event.event_type))
        |> PacketWriter.write_byte(event.phase)
        |> PacketWriter.write_uint32(event.time_remaining_ms)
        |> PacketWriter.write_uint16(event.participant_count)
      end)

    {:ok, writer}
  end

  defp event_type_to_int(:invasion), do: 0
  defp event_type_to_int(:collection), do: 1
  defp event_type_to_int(:territory), do: 2
  defp event_type_to_int(:defense), do: 3
  defp event_type_to_int(:escort), do: 4
  defp event_type_to_int(:world_boss), do: 5
  defp event_type_to_int(_), do: 0
end
```

**Step 6: Create ServerContributionUpdate**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerContributionUpdate do
  @moduledoc """
  Update player's personal contribution.

  ## Wire Format
  instance_id  : uint32
  contribution : uint32
  reward_tier  : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:instance_id, :contribution, :reward_tier]

  @impl true
  def opcode, do: 0x0A06

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint32(packet.contribution)
      |> PacketWriter.write_byte(tier_to_int(packet.reward_tier))

    {:ok, writer}
  end

  defp tier_to_int(:participation), do: 0
  defp tier_to_int(:bronze), do: 1
  defp tier_to_int(:silver), do: 2
  defp tier_to_int(:gold), do: 3
  defp tier_to_int(nil), do: 0
  defp tier_to_int(_), do: 0
end
```

**Step 7: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_*.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_contribution_update.ex
git commit -m "feat(protocol): add public event server packets"
```

---

## Task 13: Server Packets - World Boss

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_world_boss_spawn.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_world_boss_phase.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_world_boss_killed.ex`

**Step 1: Create ServerWorldBossSpawn**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerWorldBossSpawn do
  @moduledoc """
  Announce world boss spawn.

  ## Wire Format
  boss_id    : uint32
  zone_id    : uint32
  position_x : float32
  position_y : float32
  position_z : float32
  entity_guid : uint64
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :zone_id, :position_x, :position_y, :position_z, :entity_guid]

  @impl true
  def opcode, do: 0x0A10

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_uint32(packet.zone_id)
      |> PacketWriter.write_float(packet.position_x)
      |> PacketWriter.write_float(packet.position_y)
      |> PacketWriter.write_float(packet.position_z)
      |> PacketWriter.write_uint64(packet.entity_guid)

    {:ok, writer}
  end
end
```

**Step 2: Create ServerWorldBossPhase**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerWorldBossPhase do
  @moduledoc """
  Notify boss phase transition.

  ## Wire Format
  boss_id        : uint32
  entity_guid    : uint64
  phase          : uint8
  health_percent : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :entity_guid, :phase, :health_percent]

  @impl true
  def opcode, do: 0x0A11

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_uint64(packet.entity_guid)
      |> PacketWriter.write_byte(packet.phase)
      |> PacketWriter.write_byte(packet.health_percent)

    {:ok, writer}
  end
end
```

**Step 3: Create ServerWorldBossKilled**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerWorldBossKilled do
  @moduledoc """
  Announce world boss killed.

  ## Wire Format
  boss_id       : uint32
  zone_id       : uint32
  kill_time_ms  : uint32
  killer_count  : uint16
  top_damage_count : uint8
  top_damage    : [TopDamage] * count

  TopDamage:
    character_name : wstring
    damage         : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:boss_id, :zone_id, :kill_time_ms, :killer_count, top_damage: []]

  @impl true
  def opcode, do: 0x0A12

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.boss_id)
      |> PacketWriter.write_uint32(packet.zone_id)
      |> PacketWriter.write_uint32(packet.kill_time_ms)
      |> PacketWriter.write_uint16(packet.killer_count)
      |> PacketWriter.write_byte(length(packet.top_damage))

    writer =
      Enum.reduce(packet.top_damage, writer, fn entry, w ->
        w
        |> PacketWriter.write_wstring(entry.character_name)
        |> PacketWriter.write_uint32(entry.damage)
      end)

    {:ok, writer}
  end
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_world_boss_*.ex
git commit -m "feat(protocol): add world boss server packets"
```

---

## Task 14: Client Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_event_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_event_join.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_event_contribute.ex`

**Step 1: Create ClientEventList**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientEventList do
  @moduledoc """
  Request list of active events in zone.

  ## Wire Format
  (no payload - uses session zone)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: 0x0A01

  @impl true
  def read(_reader) do
    {:ok, %__MODULE__{}}
  end
end
```

**Step 2: Create ClientEventJoin**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientEventJoin do
  @moduledoc """
  Explicitly join an event.

  ## Wire Format
  instance_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id]

  @impl true
  def opcode, do: 0x0A02

  @impl true
  def read(reader) do
    {instance_id, reader} = PacketReader.read_uint32(reader)
    {:ok, %__MODULE__{instance_id: instance_id}, reader}
  end
end
```

**Step 3: Create ClientEventContribute**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientEventContribute do
  @moduledoc """
  Turn in collected items for event.

  ## Wire Format
  instance_id : uint32
  item_id     : uint32
  quantity    : uint16
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id, :item_id, :quantity]

  @impl true
  def opcode, do: 0x0A03

  @impl true
  def read(reader) do
    {instance_id, reader} = PacketReader.read_uint32(reader)
    {item_id, reader} = PacketReader.read_uint32(reader)
    {quantity, reader} = PacketReader.read_uint16(reader)

    {:ok, %__MODULE__{
      instance_id: instance_id,
      item_id: item_id,
      quantity: quantity
    }, reader}
  end
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_event_*.ex
git commit -m "feat(protocol): add public event client packets"
```

---

## Tasks 15-26: Remaining Implementation

The remaining tasks follow the same pattern. Due to length constraints, here's a summary:

### Task 15: EventManager GenServer - Core
- File: `apps/bezgelor_world/lib/bezgelor_world/event_manager.ex`
- Implements: Basic lifecycle (trigger, start, complete, fail)
- State: active_events, event_timers, scheduled_events

### Task 16: EventManager - Objectives
- Add: `record_kill/4`, `record_collection/5`, `record_damage/4`
- Implements: Objective progress tracking and completion detection

### Task 17: EventManager - Scheduling
- Add: Timer-based event triggers
- Implements: `check_schedules/0`, `calculate_next_trigger/1`

### Task 18: EventManager - World Bosses
- Add: Boss spawn windows, phase transitions
- Implements: `spawn_boss/2`, `check_boss_phase/2`, `kill_boss/1`

### Task 19: EventManager - Waves
- Add: Invasion wave system
- Implements: `advance_wave/1`, `spawn_wave/2`, `check_wave_completion/1`

### Task 20: EventManager - Territory
- Add: Control point mechanics
- Implements: `check_control_points/1`, `capture_point/2`, `tick_territory/1`

### Task 21: EventManager - Rewards
- Add: Tier calculation and distribution
- Implements: `calculate_rewards/2`, `distribute_rewards/1`

### Task 22: Event Handler
- File: `apps/bezgelor_world/lib/bezgelor_world/handler/event_handler.ex`
- Implements: Packet processing for client requests

### Task 23: Supervision Tree
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`
- Add: EventManager to children list

### Task 24: Combat Integration
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`
- Add: Kill recording calls to EventManager

### Task 25: Tests
- File: `apps/bezgelor_world/test/event_manager_test.exs`
- Implements: Unit tests for EventManager functions

### Task 26: Update STATUS.md
- Modify: `docs/STATUS.md`
- Update: Phase 9 completion status

---

## Summary

After completing all 26 tasks, Phase 9: Public Events will include:

| Component | Status |
|-----------|--------|
| Database Tables | Migration with 5 tables |
| Schemas | EventInstance, EventParticipation, EventCompletion, EventSchedule, WorldBossSpawn |
| Context | Full CRUD + participation + scheduling + boss spawns |
| Static Data | Events, bosses, spawn points JSON |
| ETS | Loaded and queryable |
| Server Packets | 9 packets for events + bosses |
| Client Packets | 3 request packets |
| EventManager | Core + objectives + scheduling + bosses + waves + territory + rewards |
| Handler | Packet processing |
| Integration | Combat kill recording |
| Tests | Comprehensive coverage |

**Features implemented:**
- Zone events with multiple phases and objectives
- World bosses with spawn windows and phase mechanics
- Invasion waves with escalation
- Territory control with capture mechanics
- Contribution-based reward tiers
- Scheduled event triggers
- Full packet protocol for client sync
