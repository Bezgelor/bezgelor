defmodule BezgelorDb.Repo.Migrations.CreateInstanceTables do
  use Ecto.Migration

  def change do
    # Instance lockouts - character lockout tracking
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

    # Instance completions - historical completion records
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

    # Instance saves - raid save states (boss kills, progress)
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

    # Group finder queue - active queue entries
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

    # Group finder groups - formed groups awaiting entry
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

    # Mythic keystones - player keystone inventory
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

    # Mythic runs - completed mythic+ runs for leaderboards
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

    # Loot history - loot distribution audit trail
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
  end
end
