defmodule BezgelorDb.Repo.Migrations.CreateActiveMountsPets do
  use Ecto.Migration

  def change do
    create table(:active_mounts) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :mount_id, :integer, null: false
      add :customization, :map, default: %{}  # dyes, flair, upgrades

      timestamps(type: :utc_datetime)
    end

    create unique_index(:active_mounts, [:character_id])

    create table(:active_pets) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :pet_id, :integer, null: false
      add :level, :integer, default: 1
      add :xp, :integer, default: 0
      add :nickname, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:active_pets, [:character_id])
  end
end
