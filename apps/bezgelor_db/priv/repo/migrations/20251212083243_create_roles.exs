defmodule BezgelorDb.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :name, :string, null: false
      add :description, :text
      add :protected, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:roles, [:name])
  end
end
