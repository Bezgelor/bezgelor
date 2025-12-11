defmodule BezgelorDb.Repo.Migrations.AddAccountTitles do
  use Ecto.Migration

  def change do
    create table(:account_titles) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :title_id, :integer, null: false
      add :unlocked_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:account_titles, [:account_id, :title_id])
    create index(:account_titles, [:account_id])

    alter table(:accounts) do
      add :active_title_id, :integer
    end
  end
end
