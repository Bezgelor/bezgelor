# Public Events System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement WildStar's public events system including zone-wide events, multi-phase objectives, participation tracking, and scaled rewards.

**Architecture:** EventManager GenServer coordinates event scheduling and lifecycle. Events run within Zone.Instance processes, tracking objectives and participants. Database stores event definitions, active instances, and participation records. Protocol packets sync event state to all zone players.

**Tech Stack:** Elixir, Ecto, GenServer, Process.send_after (timers), ETS (event definitions), Ranch TCP

---

## Overview

WildStar's public events system includes:
- **Zone Events** - Multi-objective encounters in specific zones
- **World Bosses** - Large raid encounters with spawn timers
- **Event Chains** - Sequential events that unlock subsequent events
- **Participation Rewards** - Scaled based on contribution and player count

Key mechanics:
- Events have multiple phases with different objectives
- Objectives track kills, collections, defense timers, etc.
- Rewards scale with participation count
- Events can be timer-triggered or player-triggered

---

## Critical Files

| Component | File Path |
|-----------|-----------|
| Migration | `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_public_event_tables.exs` |
| Event Definition Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/public_event.ex` |
| Event Instance Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/event_instance.ex` |
| Participation Schema | `apps/bezgelor_db/lib/bezgelor_db/schema/event_participation.ex` |
| Context Module | `apps/bezgelor_db/lib/bezgelor_db/public_events.ex` |
| Event Manager | `apps/bezgelor_world/lib/bezgelor_world/event_manager.ex` |
| Event Handler | `apps/bezgelor_world/lib/bezgelor_world/handler/event_handler.ex` |
| Server Packets | `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_*.ex` |
| Tests | `apps/bezgelor_db/test/public_events_test.exs` |

---

## Task 1: Create Public Event Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251210210000_create_public_event_tables.exs`

**Step 1: Generate migration file**

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
      add :phase_progress, :map, default: %{}
      add :participant_count, :integer, null: false, default: 0
      add :started_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:event_instances, [:zone_id, :instance_id])
    create index(:event_instances, [:state])
    create index(:event_instances, [:event_id, :state])

    # Player participation tracking
    create table(:event_participations) do
      add :event_instance_id, references(:event_instances, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :contribution_score, :integer, null: false, default: 0
      add :objectives_completed, {:array, :integer}, default: []
      add :rewards_claimed, :boolean, default: false
      add :joined_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_participations, [:event_instance_id, :character_id])
    create index(:event_participations, [:character_id])

    # Event completion history
    create table(:event_completions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :event_id, :integer, null: false
      add :completion_count, :integer, null: false, default: 1
      add :best_contribution, :integer, null: false, default: 0
      add :last_completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_completions, [:character_id, :event_id])
    create index(:event_completions, [:character_id])
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

## Task 2: Create EventInstance Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_instance.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventInstance do
  @moduledoc """
  Active public event instance.

  Tracks an in-progress event in a specific zone, including
  current phase, objective progress, and participant count.
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
    field :phase_progress, :map, default: %{}
    field :participant_count, :integer, default: 0
    field :started_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :completed_at, :utc_datetime

    has_many :participations, BezgelorDb.Schema.EventParticipation

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new event instance."
  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [:event_id, :zone_id, :instance_id, :state, :current_phase, :phase_progress, :participant_count, :started_at, :ends_at])
    |> validate_required([:event_id, :zone_id])
    |> validate_number(:current_phase, greater_than_or_equal_to: 0)
    |> validate_number(:participant_count, greater_than_or_equal_to: 0)
  end

  @doc "Changeset for starting an event."
  def start_changeset(instance, started_at, ends_at) do
    instance
    |> change(state: :active, started_at: started_at, ends_at: ends_at)
  end

  @doc "Changeset for advancing to next phase."
  def advance_phase_changeset(instance, new_phase, new_progress) do
    instance
    |> change(current_phase: new_phase, phase_progress: new_progress)
  end

  @doc "Changeset for updating phase progress."
  def progress_changeset(instance, progress) do
    instance
    |> change(phase_progress: progress)
  end

  @doc "Changeset for updating participant count."
  def participant_changeset(instance, count) do
    instance
    |> change(participant_count: count)
  end

  @doc "Changeset for completing an event."
  def complete_changeset(instance, completed_at) do
    instance
    |> change(state: :completed, completed_at: completed_at)
  end

  @doc "Changeset for failing an event."
  def fail_changeset(instance) do
    instance
    |> change(state: :failed, completed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc "Changeset for cancelling an event."
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

## Task 3: Create EventParticipation Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_participation.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventParticipation do
  @moduledoc """
  Player participation in a public event.

  Tracks contribution score, completed objectives, and reward status
  for each player participating in an event instance.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{EventInstance, Character}

  schema "event_participations" do
    belongs_to :event_instance, EventInstance
    belongs_to :character, Character
    field :contribution_score, :integer, default: 0
    field :objectives_completed, {:array, :integer}, default: []
    field :rewards_claimed, :boolean, default: false
    field :joined_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for joining an event."
  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [:event_instance_id, :character_id, :contribution_score, :objectives_completed, :joined_at])
    |> validate_required([:event_instance_id, :character_id])
    |> validate_number(:contribution_score, greater_than_or_equal_to: 0)
    |> unique_constraint([:event_instance_id, :character_id])
    |> foreign_key_constraint(:event_instance_id)
    |> foreign_key_constraint(:character_id)
  end

  @doc "Changeset for adding contribution."
  def contribute_changeset(participation, points) do
    new_score = participation.contribution_score + points

    participation
    |> change(contribution_score: new_score)
  end

  @doc "Changeset for completing an objective."
  def complete_objective_changeset(participation, objective_index) do
    objectives =
      if objective_index in participation.objectives_completed do
        participation.objectives_completed
      else
        [objective_index | participation.objectives_completed]
      end

    participation
    |> change(objectives_completed: objectives)
  end

  @doc "Changeset for claiming rewards."
  def claim_rewards_changeset(participation) do
    participation
    |> change(rewards_claimed: true)
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_participation.ex
git commit -m "feat(db): add EventParticipation schema"
```

---

## Task 4: Create EventCompletion Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/event_completion.ex`

**Step 1: Write schema**

```elixir
defmodule BezgelorDb.Schema.EventCompletion do
  @moduledoc """
  Historical record of event completions per character.

  Tracks how many times a character has completed each event
  and their best contribution score.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "event_completions" do
    belongs_to :character, Character
    field :event_id, :integer
    field :completion_count, :integer, default: 1
    field :best_contribution, :integer, default: 0
    field :last_completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for first completion."
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:character_id, :event_id, :completion_count, :best_contribution, :last_completed_at])
    |> validate_required([:character_id, :event_id])
    |> validate_number(:completion_count, greater_than: 0)
    |> validate_number(:best_contribution, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :event_id])
    |> foreign_key_constraint(:character_id)
  end

  @doc "Changeset for incrementing completion count."
  def increment_changeset(completion, contribution, completed_at) do
    best = max(completion.best_contribution, contribution)

    completion
    |> change(
      completion_count: completion.completion_count + 1,
      best_contribution: best,
      last_completed_at: completed_at
    )
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/event_completion.ex
git commit -m "feat(db): add EventCompletion schema"
```

---

## Task 5: Create PublicEvents Context - Core Functions

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
      name: "EventHero",
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
      assert instance.state == :pending
    end
  end

  describe "start_event/2" do
    test "starts a pending event" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)

      assert {:ok, started} = PublicEvents.start_event(instance.id, 300_000)
      assert started.state == :active
      assert started.started_at != nil
    end
  end

  describe "join_event/2" do
    test "player joins an active event", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, participation} = PublicEvents.join_event(instance.id, char.id)
      assert participation.character_id == char.id
      assert participation.contribution_score == 0
    end

    test "cannot join same event twice", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:error, :already_joined} = PublicEvents.join_event(instance.id, char.id)
    end
  end

  describe "add_contribution/3" do
    test "adds contribution to participant", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.add_contribution(instance.id, char.id, 50)
      assert updated.contribution_score == 50

      assert {:ok, again} = PublicEvents.add_contribution(instance.id, char.id, 30)
      assert again.contribution_score == 80
    end
  end

  describe "get_active_events/1" do
    test "returns active events in zone" do
      {:ok, _} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, instance} = PublicEvents.create_event_instance(2, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      active = PublicEvents.get_active_events(100)
      assert length(active) == 1
      assert hd(active).event_id == 2
    end
  end

  describe "complete_event/1" do
    test "marks event as completed", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 100)

      assert {:ok, completed} = PublicEvents.complete_event(instance.id)
      assert completed.state == :completed
    end

    test "records completion history", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 100)
      {:ok, _} = PublicEvents.complete_event(instance.id)

      history = PublicEvents.get_completion_history(char.id, 1)
      assert history.completion_count == 1
      assert history.best_contribution == 100
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: FAIL with "module BezgelorDb.PublicEvents is not available"

**Step 3: Write minimal implementation**

```elixir
defmodule BezgelorDb.PublicEvents do
  @moduledoc """
  Public events management context.

  Handles event instances, participation tracking, contributions,
  and completion history.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{EventInstance, EventParticipation, EventCompletion}

  # Event Instance Management

  @doc "Get an event instance by ID."
  @spec get_event_instance(integer()) :: EventInstance.t() | nil
  def get_event_instance(instance_id) do
    Repo.get(EventInstance, instance_id)
  end

  @doc "Get all active events in a zone."
  @spec get_active_events(integer(), integer()) :: [EventInstance.t()]
  def get_active_events(zone_id, instance_id \\ 1) do
    EventInstance
    |> where([e], e.zone_id == ^zone_id and e.instance_id == ^instance_id)
    |> where([e], e.state == :active)
    |> order_by([e], asc: e.started_at)
    |> Repo.all()
  end

  @doc "Create a new event instance."
  @spec create_event_instance(integer(), integer(), integer()) :: {:ok, EventInstance.t()} | {:error, term()}
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
  @spec start_event(integer(), integer()) :: {:ok, EventInstance.t()} | {:error, term()}
  def start_event(instance_id, duration_ms) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ends_at = DateTime.add(now, duration_ms, :millisecond)

        instance
        |> EventInstance.start_changeset(now, ends_at)
        |> Repo.update()
    end
  end

  @doc "Complete an event successfully."
  @spec complete_event(integer()) :: {:ok, EventInstance.t()} | {:error, term()}
  def complete_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.transaction(fn ->
          # Complete the instance
          {:ok, completed} =
            instance
            |> EventInstance.complete_changeset(now)
            |> Repo.update()

          # Record completion for all participants
          participations = get_participations(instance_id)

          Enum.each(participations, fn p ->
            record_completion(p.character_id, instance.event_id, p.contribution_score, now)
          end)

          completed
        end)
    end
  end

  @doc "Fail an event."
  @spec fail_event(integer()) :: {:ok, EventInstance.t()} | {:error, term()}
  def fail_event(instance_id) do
    case get_event_instance(instance_id) do
      nil -> {:error, :not_found}
      instance ->
        instance
        |> EventInstance.fail_changeset()
        |> Repo.update()
    end
  end

  @doc "Cancel an event."
  @spec cancel_event(integer()) :: {:ok, EventInstance.t()} | {:error, term()}
  def cancel_event(instance_id) do
    case get_event_instance(instance_id) do
      nil -> {:error, :not_found}
      instance ->
        instance
        |> EventInstance.cancel_changeset()
        |> Repo.update()
    end
  end

  # Phase Management

  @doc "Advance to next phase."
  @spec advance_phase(integer(), integer(), map()) :: {:ok, EventInstance.t()} | {:error, term()}
  def advance_phase(instance_id, new_phase, initial_progress) do
    case get_event_instance(instance_id) do
      nil -> {:error, :not_found}
      instance ->
        instance
        |> EventInstance.advance_phase_changeset(new_phase, initial_progress)
        |> Repo.update()
    end
  end

  @doc "Update phase progress."
  @spec update_progress(integer(), map()) :: {:ok, EventInstance.t()} | {:error, term()}
  def update_progress(instance_id, progress) do
    case get_event_instance(instance_id) do
      nil -> {:error, :not_found}
      instance ->
        instance
        |> EventInstance.progress_changeset(progress)
        |> Repo.update()
    end
  end

  # Participation Management

  @doc "Get participation record."
  @spec get_participation(integer(), integer()) :: EventParticipation.t() | nil
  def get_participation(instance_id, character_id) do
    Repo.get_by(EventParticipation, event_instance_id: instance_id, character_id: character_id)
  end

  @doc "Get all participations for an event."
  @spec get_participations(integer()) :: [EventParticipation.t()]
  def get_participations(instance_id) do
    EventParticipation
    |> where([p], p.event_instance_id == ^instance_id)
    |> order_by([p], desc: p.contribution_score)
    |> Repo.all()
  end

  @doc "Join an event."
  @spec join_event(integer(), integer()) :: {:ok, EventParticipation.t()} | {:error, term()}
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
          joined_at: now
        })
        |> Repo.insert()

      # Update participant count
      case result do
        {:ok, participation} ->
          update_participant_count(instance_id)
          {:ok, participation}

        error ->
          error
      end
    end
  end

  @doc "Add contribution points."
  @spec add_contribution(integer(), integer(), integer()) :: {:ok, EventParticipation.t()} | {:error, term()}
  def add_contribution(instance_id, character_id, points) do
    case get_participation(instance_id, character_id) do
      nil -> {:error, :not_participating}
      participation ->
        participation
        |> EventParticipation.contribute_changeset(points)
        |> Repo.update()
    end
  end

  @doc "Mark objective completed for participant."
  @spec complete_objective(integer(), integer(), integer()) :: {:ok, EventParticipation.t()} | {:error, term()}
  def complete_objective(instance_id, character_id, objective_index) do
    case get_participation(instance_id, character_id) do
      nil -> {:error, :not_participating}
      participation ->
        participation
        |> EventParticipation.complete_objective_changeset(objective_index)
        |> Repo.update()
    end
  end

  # Completion History

  @doc "Get completion history for a character and event."
  @spec get_completion_history(integer(), integer()) :: EventCompletion.t() | nil
  def get_completion_history(character_id, event_id) do
    Repo.get_by(EventCompletion, character_id: character_id, event_id: event_id)
  end

  @doc "Get all completions for a character."
  @spec get_all_completions(integer()) :: [EventCompletion.t()]
  def get_all_completions(character_id) do
    EventCompletion
    |> where([c], c.character_id == ^character_id)
    |> order_by([c], desc: c.last_completed_at)
    |> Repo.all()
  end

  # Private Helpers

  defp update_participant_count(instance_id) do
    count =
      EventParticipation
      |> where([p], p.event_instance_id == ^instance_id)
      |> Repo.aggregate(:count)

    case get_event_instance(instance_id) do
      nil -> :ok
      instance ->
        instance
        |> EventInstance.participant_changeset(count)
        |> Repo.update()
    end
  end

  defp record_completion(character_id, event_id, contribution, completed_at) do
    case get_completion_history(character_id, event_id) do
      nil ->
        %EventCompletion{}
        |> EventCompletion.changeset(%{
          character_id: character_id,
          event_id: event_id,
          best_contribution: contribution,
          last_completed_at: completed_at
        })
        |> Repo.insert()

      existing ->
        existing
        |> EventCompletion.increment_changeset(contribution, completed_at)
        |> Repo.update()
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/public_events.ex apps/bezgelor_db/test/public_events_test.exs
git commit -m "feat(db): add PublicEvents context"
```

---

## Task 6: Create Server Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_start.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_update.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_complete.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_objective.ex`

**Step 1: Create ServerEventStart**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEventStart do
  @moduledoc """
  Notify client that a public event has started.

  ## Wire Format
  instance_id     : uint32
  event_id        : uint32
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

  defstruct [:instance_id, :event_id, :phase, :duration_ms, objectives: []]

  @impl true
  def opcode, do: :server_event_start

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint32(packet.event_id)
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

  defp objective_type_to_int(:kill), do: 0
  defp objective_type_to_int(:collect), do: 1
  defp objective_type_to_int(:defend), do: 2
  defp objective_type_to_int(:interact), do: 3
  defp objective_type_to_int(:survive), do: 4
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
  def opcode, do: :server_event_update

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

  defstruct [:instance_id, :event_id, :success, :contribution, :reward_xp, :reward_gold, rewards: []]

  @impl true
  def opcode, do: :server_event_complete

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.instance_id)
      |> PacketWriter.write_uint32(packet.event_id)
      |> PacketWriter.write_byte(if(packet.success, do: 1, else: 0))
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
  def opcode, do: :server_event_phase

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
  defp objective_type_to_int(:collect), do: 1
  defp objective_type_to_int(:defend), do: 2
  defp objective_type_to_int(:interact), do: 3
  defp objective_type_to_int(:survive), do: 4
  defp objective_type_to_int(_), do: 0
end
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_start.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_update.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_complete.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_event_phase.ex
git commit -m "feat(protocol): add public event server packets"
```

---

## Task 7: Create EventManager GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/event_manager.ex`

**Step 1: Write EventManager**

```elixir
defmodule BezgelorWorld.EventManager do
  @moduledoc """
  Manages public events across all zones.

  Responsibilities:
  - Schedule and trigger events based on timers
  - Track active events per zone
  - Process event objectives and phase transitions
  - Distribute rewards on completion
  """

  use GenServer

  require Logger

  alias BezgelorDb.PublicEvents
  alias BezgelorWorld.{WorldManager, Zone}
  alias BezgelorProtocol.Packets.World.{
    ServerEventStart,
    ServerEventUpdate,
    ServerEventComplete,
    ServerEventPhase
  }

  @default_event_duration 300_000  # 5 minutes

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger an event in a zone."
  @spec trigger_event(integer(), integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def trigger_event(event_id, zone_id, instance_id \\ 1) do
    GenServer.call(__MODULE__, {:trigger_event, event_id, zone_id, instance_id})
  end

  @doc "Record a kill for event objectives."
  @spec record_kill(integer(), integer(), integer(), integer()) :: :ok
  def record_kill(zone_id, instance_id, creature_id, killer_guid) do
    GenServer.cast(__MODULE__, {:record_kill, zone_id, instance_id, creature_id, killer_guid})
  end

  @doc "Record item collection for event objectives."
  @spec record_collection(integer(), integer(), integer(), integer(), integer()) :: :ok
  def record_collection(zone_id, instance_id, item_id, collector_guid, count) do
    GenServer.cast(__MODULE__, {:record_collection, zone_id, instance_id, item_id, collector_guid, count})
  end

  @doc "Get active events in a zone."
  @spec get_zone_events(integer(), integer()) :: [map()]
  def get_zone_events(zone_id, instance_id \\ 1) do
    GenServer.call(__MODULE__, {:get_zone_events, zone_id, instance_id})
  end

  @doc "Player joins an event."
  @spec player_join_event(integer(), integer()) :: {:ok, term()} | {:error, term()}
  def player_join_event(event_instance_id, character_id) do
    GenServer.call(__MODULE__, {:player_join, event_instance_id, character_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      active_events: %{},       # {zone_id, instance_id} => [event_instance_ids]
      event_timers: %{},        # event_instance_id => timer_ref
      event_definitions: %{}    # event_id => definition (loaded from BezgelorData)
    }

    Logger.info("EventManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:trigger_event, event_id, zone_id, instance_id}, _from, state) do
    # TODO: Load event definition from BezgelorData
    event_def = get_event_definition(state, event_id)

    case PublicEvents.create_event_instance(event_id, zone_id, instance_id) do
      {:ok, instance} ->
        duration = Map.get(event_def, :duration, @default_event_duration)

        case PublicEvents.start_event(instance.id, duration) do
          {:ok, started} ->
            # Schedule event end timer
            timer_ref = Process.send_after(self(), {:event_timeout, instance.id}, duration)

            # Update state
            key = {zone_id, instance_id}
            active = Map.get(state.active_events, key, [])
            new_active = Map.put(state.active_events, key, [instance.id | active])
            new_timers = Map.put(state.event_timers, instance.id, timer_ref)

            # Broadcast to zone
            broadcast_event_start(started, zone_id, instance_id, event_def)

            Logger.info("Event #{event_id} started in zone #{zone_id}")
            {:reply, {:ok, instance.id}, %{state | active_events: new_active, event_timers: new_timers}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_zone_events, zone_id, instance_id}, _from, state) do
    events = PublicEvents.get_active_events(zone_id, instance_id)
    {:reply, events, state}
  end

  @impl true
  def handle_call({:player_join, event_instance_id, character_id}, _from, state) do
    result = PublicEvents.join_event(event_instance_id, character_id)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:record_kill, zone_id, instance_id, creature_id, killer_guid}, state) do
    key = {zone_id, instance_id}
    event_ids = Map.get(state.active_events, key, [])

    Enum.each(event_ids, fn event_instance_id ->
      process_kill_objective(event_instance_id, creature_id, killer_guid, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_collection, zone_id, instance_id, item_id, collector_guid, count}, state) do
    key = {zone_id, instance_id}
    event_ids = Map.get(state.active_events, key, [])

    Enum.each(event_ids, fn event_instance_id ->
      process_collection_objective(event_instance_id, item_id, collector_guid, count, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:event_timeout, instance_id}, state) do
    case PublicEvents.get_event_instance(instance_id) do
      nil ->
        {:noreply, state}

      instance when instance.state == :active ->
        # Event timed out - fail it
        Logger.info("Event #{instance_id} timed out")
        {:ok, _} = PublicEvents.fail_event(instance_id)

        broadcast_event_complete(instance, false)
        state = remove_event_from_state(state, instance)

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Private Helpers

  defp get_event_definition(state, event_id) do
    # TODO: Load from BezgelorData
    Map.get(state.event_definitions, event_id, %{
      phases: [
        %{
          objectives: [
            %{type: :kill, creature_id: 1000, target: 10}
          ]
        }
      ],
      duration: @default_event_duration,
      rewards: %{xp: 500, gold: 100}
    })
  end

  defp process_kill_objective(event_instance_id, creature_id, killer_guid, _state) do
    case PublicEvents.get_event_instance(event_instance_id) do
      nil ->
        :ok

      instance ->
        # Check if this kill matches any objective
        progress = instance.phase_progress
        objectives = Map.get(progress, "objectives", [])

        {updated_objectives, matched} =
          Enum.map_reduce(objectives, false, fn obj, matched ->
            if obj["type"] == "kill" and obj["creature_id"] == creature_id do
              current = obj["current"] + 1
              {Map.put(obj, "current", current), true}
            else
              {obj, matched}
            end
          end)

        if matched do
          new_progress = Map.put(progress, "objectives", updated_objectives)
          {:ok, updated} = PublicEvents.update_progress(event_instance_id, new_progress)

          # Add contribution to killer
          character_id = guid_to_character_id(killer_guid)
          if character_id, do: PublicEvents.add_contribution(event_instance_id, character_id, 10)

          # Broadcast update
          broadcast_objective_update(updated, updated_objectives)

          # Check for phase completion
          check_phase_completion(updated, updated_objectives)
        end
    end
  end

  defp process_collection_objective(event_instance_id, item_id, collector_guid, count, _state) do
    case PublicEvents.get_event_instance(event_instance_id) do
      nil ->
        :ok

      instance ->
        progress = instance.phase_progress
        objectives = Map.get(progress, "objectives", [])

        {updated_objectives, matched} =
          Enum.map_reduce(objectives, false, fn obj, matched ->
            if obj["type"] == "collect" and obj["item_id"] == item_id do
              current = min(obj["current"] + count, obj["target"])
              {Map.put(obj, "current", current), true}
            else
              {obj, matched}
            end
          end)

        if matched do
          new_progress = Map.put(progress, "objectives", updated_objectives)
          {:ok, updated} = PublicEvents.update_progress(event_instance_id, new_progress)

          character_id = guid_to_character_id(collector_guid)
          if character_id, do: PublicEvents.add_contribution(event_instance_id, character_id, 5 * count)

          broadcast_objective_update(updated, updated_objectives)
          check_phase_completion(updated, updated_objectives)
        end
    end
  end

  defp check_phase_completion(instance, objectives) do
    all_complete = Enum.all?(objectives, fn obj ->
      obj["current"] >= obj["target"]
    end)

    if all_complete do
      # TODO: Check if more phases, advance or complete event
      complete_event(instance)
    end
  end

  defp complete_event(instance) do
    {:ok, completed} = PublicEvents.complete_event(instance.id)
    broadcast_event_complete(completed, true)
    Logger.info("Event #{instance.id} completed successfully")
  end

  defp broadcast_event_start(instance, zone_id, zone_instance_id, event_def) do
    phase_def = Enum.at(event_def.phases, instance.current_phase, %{objectives: []})

    objectives =
      Enum.with_index(phase_def.objectives)
      |> Enum.map(fn {obj, idx} ->
        %{
          index: idx,
          type: obj.type,
          target: obj.target,
          current: 0
        }
      end)

    packet = %ServerEventStart{
      instance_id: instance.id,
      event_id: instance.event_id,
      phase: instance.current_phase,
      duration_ms: @default_event_duration,
      objectives: objectives
    }

    broadcast_to_zone(zone_id, zone_instance_id, packet)
  end

  defp broadcast_objective_update(instance, objectives) do
    Enum.each(objectives, fn obj ->
      packet = %ServerEventUpdate{
        instance_id: instance.id,
        objective_index: obj["index"] || 0,
        current: obj["current"],
        target: obj["target"]
      }

      broadcast_to_zone(instance.zone_id, instance.instance_id, packet)
    end)
  end

  defp broadcast_event_complete(instance, success) do
    participations = PublicEvents.get_participations(instance.id)

    Enum.each(participations, fn p ->
      # Calculate rewards based on contribution
      base_xp = 500
      base_gold = 100
      contribution_bonus = div(p.contribution_score, 10)

      packet = %ServerEventComplete{
        instance_id: instance.id,
        event_id: instance.event_id,
        success: success,
        contribution: p.contribution_score,
        reward_xp: if(success, do: base_xp + contribution_bonus, else: div(base_xp, 4)),
        reward_gold: if(success, do: base_gold + contribution_bonus, else: 0),
        rewards: []
      }

      send_to_character(p.character_id, packet)
    end)
  end

  defp broadcast_to_zone(zone_id, zone_instance_id, packet) do
    # Get all players in zone and send packet
    case Zone.Instance.whereis({zone_id, zone_instance_id}) do
      nil ->
        :ok

      pid ->
        players = Zone.Instance.list_players(pid)

        Enum.each(players, fn player ->
          send_to_player(player.guid, packet)
        end)
    end
  end

  defp send_to_player(player_guid, packet) do
    sessions = WorldManager.list_sessions()

    case Enum.find(sessions, fn {_id, s} -> s.entity_guid == player_guid end) do
      nil -> :ok
      {_id, session} -> send(session.connection_pid, {:send_packet, packet})
    end
  end

  defp send_to_character(character_id, packet) do
    sessions = WorldManager.list_sessions()

    case Enum.find(sessions, fn {_id, s} -> s.character_id == character_id end) do
      nil -> :ok
      {_id, session} -> send(session.connection_pid, {:send_packet, packet})
    end
  end

  defp guid_to_character_id(guid) do
    sessions = WorldManager.list_sessions()

    case Enum.find(sessions, fn {_id, s} -> s.entity_guid == guid end) do
      nil -> nil
      {_id, session} -> session.character_id
    end
  end

  defp remove_event_from_state(state, instance) do
    key = {instance.zone_id, instance.instance_id}
    active = Map.get(state.active_events, key, [])
    new_active = List.delete(active, instance.id)

    new_active_events =
      if new_active == [] do
        Map.delete(state.active_events, key)
      else
        Map.put(state.active_events, key, new_active)
      end

    # Cancel timer if exists
    case Map.get(state.event_timers, instance.id) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    new_timers = Map.delete(state.event_timers, instance.id)

    %{state | active_events: new_active_events, event_timers: new_timers}
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/event_manager.ex
git commit -m "feat(world): add EventManager GenServer"
```

---

## Task 8: Add EventManager to Supervision Tree

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`

**Step 1: Add to children list**

Find the `base_children` list and add EventManager:

```elixir
base_children = [
  BezgelorWorld.WorldManager,
  BezgelorWorld.CreatureManager,
  BezgelorWorld.BuffManager,
  BezgelorWorld.EventManager,  # Add this line
  BezgelorWorld.Zone.InstanceSupervisor
]
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/application.ex
git commit -m "feat(world): add EventManager to supervision tree"
```

---

## Task 9: Integrate Event Recording with Combat

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`

**Step 1: Add event recording to creature kills**

In `apply_spell_effects/5`, after a creature is killed, add:

```elixir
# After CreatureManager.damage_creature returns {:ok, :killed, result}
# Add event recording:
defp apply_spell_effects(caster_guid, target_guid, spell, effects, state) do
  # ... existing code ...

  {effect_packets, kill_info} =
    Enum.reduce(effects, {[], nil}, fn effect, {packets, info} ->
      target = if spell.target_type == :self, do: caster_guid, else: target_guid
      packet = build_effect_packet(caster_guid, target, spell.id, effect)

      new_info =
        if effect.type == :damage and is_creature_guid?(target) do
          case CreatureManager.damage_creature(target, caster_guid, effect.amount) do
            {:ok, :killed, result} ->
              # Record kill for public events
              zone_id = state.session_data[:zone_id] || 1
              instance_id = state.session_data[:instance_id] || 1
              creature_id = result.creature_template_id || 0

              BezgelorWorld.EventManager.record_kill(
                zone_id,
                instance_id,
                creature_id,
                caster_guid
              )

              %{creature_guid: target, rewards: result}

            {:ok, :damaged, _result} ->
              info

            {:error, _reason} ->
              info
          end
        else
          info
        end

      {[packet | packets], new_info || info}
    end)

  {Enum.reverse(effect_packets), kill_info}
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex
git commit -m "feat(world): integrate event kill recording into combat"
```

---

## Task 10: Run Full Test Suite

**Step 1: Run public events tests**

Run: `cd . && MIX_ENV=test mix test apps/bezgelor_db/test/public_events_test.exs --trace`
Expected: All tests pass

**Step 2: Run full test suite**

Run: `cd . && MIX_ENV=test mix test`
Expected: All tests pass

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "test: ensure public events integration works"
```

---

## Summary

After completing all tasks:

| Component | Status |
|-----------|--------|
| Migration | ✓ Tables for instances, participation, completions |
| Schemas | ✓ EventInstance, EventParticipation, EventCompletion |
| Context | ✓ Full event lifecycle management |
| Server Packets | ✓ Start, Update, Complete, Phase |
| EventManager | ✓ GenServer coordinating events |
| Supervision | ✓ Added to application tree |
| Combat Integration | ✓ Kill recording for objectives |
| Tests | ✓ Database layer tested |

**Future enhancements (not in this plan):**
1. Event definitions loaded from BezgelorData
2. World boss spawn timers and PAP triggering
3. Event chains (completion triggers next event)
4. Defense/survival objective types with timers
5. Player-triggered events (Soldier path)
6. Scaled rewards based on participant count
7. Event schedule system (daily/weekly events)
8. Admin commands to trigger events
