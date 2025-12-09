defmodule BezgelorDb.Repo.Migrations.CreateCharacters do
  use Ecto.Migration

  def change do
    create table(:characters, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, size: 24, null: false
      add :sex, :smallint, null: false
      add :race, :smallint, null: false
      add :class, :smallint, null: false
      add :level, :smallint, null: false, default: 1
      add :faction_id, :smallint, null: false

      # Position
      add :location_x, :float, null: false, default: 0.0
      add :location_y, :float, null: false, default: 0.0
      add :location_z, :float, null: false, default: 0.0
      add :rotation_x, :float, null: false, default: 0.0
      add :rotation_y, :float, null: false, default: 0.0
      add :rotation_z, :float, null: false, default: 0.0
      add :world_id, :smallint, null: false
      add :world_zone_id, :smallint, null: false

      # State
      add :title, :smallint, default: 0
      add :active_path, :integer, default: 0
      add :active_costume_index, :smallint, default: -1
      add :active_spec, :smallint, default: 0
      add :innate_index, :smallint, default: 0
      add :total_xp, :integer, default: 0
      add :rest_bonus_xp, :integer, default: 0
      add :time_played_total, :integer, default: 0
      add :time_played_level, :integer, default: 0
      add :flags, :integer, default: 0

      # Timestamps
      add :last_online, :utc_datetime
      add :deleted_at, :utc_datetime
      add :original_name, :string, size: 24

      timestamps(type: :utc_datetime)
    end

    create unique_index(:characters, [:name], where: "deleted_at IS NULL")
    create index(:characters, [:account_id])
  end
end
