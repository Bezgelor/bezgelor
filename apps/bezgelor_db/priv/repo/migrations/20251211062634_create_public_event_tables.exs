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
