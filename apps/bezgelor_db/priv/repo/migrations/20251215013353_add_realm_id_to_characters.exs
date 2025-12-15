defmodule BezgelorDb.Repo.Migrations.AddRealmIdToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :realm_id, references(:realms, on_delete: :restrict), null: false, default: 1
    end

    create index(:characters, [:realm_id])
    create index(:characters, [:account_id, :realm_id])
  end
end
