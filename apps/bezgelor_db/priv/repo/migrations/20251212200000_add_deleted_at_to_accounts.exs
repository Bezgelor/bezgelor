defmodule BezgelorDb.Repo.Migrations.AddDeletedAtToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :deleted_at, :utc_datetime, null: true
    end

    # Index for querying non-deleted accounts
    create index(:accounts, [:deleted_at])
  end
end
