defmodule BezgelorDb.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:account_collections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :collectible_type, :string, null: false  # "mount" or "pet"
      add :collectible_id, :integer, null: false
      add :unlock_source, :string  # purchase, achievement, promo, gift

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_collections, [:account_id, :collectible_type, :collectible_id])
    create index(:account_collections, [:account_id, :collectible_type])

    create table(:character_collections) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :collectible_type, :string, null: false
      add :collectible_id, :integer, null: false
      add :unlock_source, :string  # quest, drop, event

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_collections, [:character_id, :collectible_type, :collectible_id])
    create index(:character_collections, [:character_id, :collectible_type])
  end
end
