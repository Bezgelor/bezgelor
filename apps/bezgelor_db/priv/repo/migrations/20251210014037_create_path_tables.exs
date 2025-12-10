defmodule BezgelorDb.Repo.Migrations.CreatePathTables do
  use Ecto.Migration

  def change do
    # Character path progression
    create table(:character_paths) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :path_type, :integer, null: false  # 0=Soldier, 1=Settler, 2=Scientist, 3=Explorer
      add :path_xp, :integer, default: 0
      add :path_level, :integer, default: 1
      add :unlocked_abilities, {:array, :integer}, default: []

      timestamps(type: :utc_datetime)
    end

    # One path per character
    create unique_index(:character_paths, [:character_id])
    create index(:character_paths, [:path_type])

    # Path mission progress
    create table(:path_missions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :mission_id, :integer, null: false  # References BezgelorData
      add :state, :string, default: "active"  # active, completed, failed
      add :progress, :map, default: %{}
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One record per mission per character
    create unique_index(:path_missions, [:character_id, :mission_id])
    create index(:path_missions, [:character_id, :state])
  end
end
