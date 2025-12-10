defmodule BezgelorDb.Repo.Migrations.CreateCharacterAppearances do
  use Ecto.Migration

  def change do
    create table(:character_appearances, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :character_id, references(:characters, on_delete: :delete_all), null: false

      # Body
      add :body_type, :smallint, null: false, default: 0
      add :body_height, :smallint, null: false, default: 0
      add :body_weight, :smallint, null: false, default: 0

      # Face
      add :face_type, :smallint, null: false, default: 0
      add :eye_type, :smallint, null: false, default: 0
      add :eye_color, :smallint, null: false, default: 0
      add :nose_type, :smallint, null: false, default: 0
      add :mouth_type, :smallint, null: false, default: 0
      add :ear_type, :smallint, null: false, default: 0

      # Hair
      add :hair_style, :smallint, null: false, default: 0
      add :hair_color, :smallint, null: false, default: 0
      add :facial_hair, :smallint, null: false, default: 0

      # Skin
      add :skin_color, :smallint, null: false, default: 0

      # Race-specific features
      add :feature_1, :smallint, null: false, default: 0
      add :feature_2, :smallint, null: false, default: 0
      add :feature_3, :smallint, null: false, default: 0
      add :feature_4, :smallint, null: false, default: 0

      # Bone customization sliders (array of floats)
      add :bones, {:array, :float}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    # Each character can only have one appearance record
    create unique_index(:character_appearances, [:character_id])
  end
end
