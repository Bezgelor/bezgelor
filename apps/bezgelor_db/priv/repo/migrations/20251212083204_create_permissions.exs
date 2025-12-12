defmodule BezgelorDb.Repo.Migrations.CreatePermissions do
  use Ecto.Migration

  def change do
    create table(:permissions) do
      add :key, :string, null: false
      add :category, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:permissions, [:key])
    create index(:permissions, [:category])
  end
end
