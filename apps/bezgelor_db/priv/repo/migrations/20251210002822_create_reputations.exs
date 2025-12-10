defmodule BezgelorDb.Repo.Migrations.CreateReputations do
  use Ecto.Migration

  def change do
    create table(:reputations) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :faction_id, :integer, null: false
      add :standing, :integer, default: 0
      timestamps()
    end

    create unique_index(:reputations, [:character_id, :faction_id])
    create index(:reputations, [:faction_id])
  end
end
