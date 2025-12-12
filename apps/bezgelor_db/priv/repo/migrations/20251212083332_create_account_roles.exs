defmodule BezgelorDb.Repo.Migrations.CreateAccountRoles do
  use Ecto.Migration

  def change do
    create table(:account_roles, primary_key: false) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      add :assigned_by, references(:accounts, on_delete: :nilify_all)
      add :assigned_at, :utc_datetime, null: false
    end

    create unique_index(:account_roles, [:account_id, :role_id])
    create index(:account_roles, [:role_id])
  end
end
