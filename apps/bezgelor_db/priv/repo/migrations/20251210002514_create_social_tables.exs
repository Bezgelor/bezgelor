defmodule BezgelorDb.Repo.Migrations.CreateSocialTables do
  use Ecto.Migration

  def change do
    create table(:friends) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :friend_character_id, references(:characters, on_delete: :delete_all), null: false
      add :note, :string, size: 256, default: ""
      add :group_name, :string, size: 64, default: "Friends"
      timestamps()
    end

    create unique_index(:friends, [:character_id, :friend_character_id])
    create index(:friends, [:friend_character_id])

    create table(:ignores) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :ignored_character_id, references(:characters, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:ignores, [:character_id, :ignored_character_id])
  end
end
