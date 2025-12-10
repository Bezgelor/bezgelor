defmodule BezgelorDb.Repo.Migrations.CreateQuestTables do
  use Ecto.Migration

  def change do
    # Active quests table
    create table(:quests) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :quest_id, :integer, null: false

      add :state, :string, null: false, default: "accepted"
      add :progress, :map, default: %{}

      add :accepted_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One active quest per character per quest_id
    create unique_index(:quests, [:character_id, :quest_id])
    create index(:quests, [:character_id])
    create index(:quests, [:character_id, :state])

    # Quest history table (normalized for efficient queries)
    create table(:quest_history) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :quest_id, :integer, null: false

      add :completed_at, :utc_datetime, null: false
      add :completion_count, :integer, null: false, default: 1
      add :last_completion, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One history entry per character per quest
    create unique_index(:quest_history, [:character_id, :quest_id])
    create index(:quest_history, [:character_id])
    create index(:quest_history, [:quest_id])
  end
end
