defmodule BezgelorDb.Repo.Migrations.CreateHousingTables do
  use Ecto.Migration

  def change do
    # Permission level enum
    execute(
      "CREATE TYPE housing_permission AS ENUM ('private', 'neighbors', 'roommates', 'public')",
      "DROP TYPE housing_permission"
    )

    # Main plot table - one per character
    create table(:housing_plots) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :house_type_id, :integer, null: false, default: 1  # 1 = cozy, 2 = spacious
      add :permission_level, :housing_permission, null: false, default: "private"
      add :sky_id, :integer, null: false, default: 1
      add :ground_id, :integer, null: false, default: 1
      add :music_id, :integer, null: false, default: 1
      add :plot_name, :string, size: 64

      timestamps(type: :utc_datetime)
    end

    create unique_index(:housing_plots, [:character_id])

    # Neighbors and roommates
    create table(:housing_neighbors) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :is_roommate, :boolean, null: false, default: false

      add :added_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:housing_neighbors, [:plot_id, :character_id])
    create index(:housing_neighbors, [:character_id])

    # Placed decor items
    create table(:housing_decor) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :decor_id, :integer, null: false  # Template from decor_items.json

      # Position (floats)
      add :pos_x, :float, null: false, default: 0.0
      add :pos_y, :float, null: false, default: 0.0
      add :pos_z, :float, null: false, default: 0.0

      # Rotation (euler angles in degrees)
      add :rot_pitch, :float, null: false, default: 0.0
      add :rot_yaw, :float, null: false, default: 0.0
      add :rot_roll, :float, null: false, default: 0.0

      # Scale
      add :scale, :float, null: false, default: 1.0

      # Interior vs exterior
      add :is_exterior, :boolean, null: false, default: false

      add :placed_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:housing_decor, [:plot_id])

    # FABkit installations
    create table(:housing_fabkits) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :socket_index, :integer, null: false  # 0-5 (4-5 are large sockets)
      add :fabkit_id, :integer, null: false  # Template from fabkit_types.json
      add :state, :map, null: false, default: fragment("'{}'::jsonb")  # harvest_available_at, challenge_progress, etc.

      add :installed_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:housing_fabkits, [:plot_id, :socket_index])
  end
end
