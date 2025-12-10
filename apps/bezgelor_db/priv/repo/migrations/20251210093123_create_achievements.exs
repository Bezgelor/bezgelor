defmodule BezgelorDb.Repo.Migrations.CreateAchievements do
  use Ecto.Migration

  def change do
    create table(:achievements) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :achievement_id, :integer, null: false

      # Progress tracking
      add :progress, :integer, null: false, default: 0
      add :criteria_progress, :map, default: %{}

      # Completion
      add :completed, :boolean, null: false, default: false
      add :completed_at, :utc_datetime

      # Points
      add :points_awarded, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # One entry per character per achievement
    create unique_index(:achievements, [:character_id, :achievement_id])
    create index(:achievements, [:character_id])
    create index(:achievements, [:character_id, :completed])
    create index(:achievements, [:achievement_id])
  end
end
