defmodule BezgelorDb.Repo.Migrations.CreateAccountSuspensions do
  use Ecto.Migration

  def change do
    create table(:account_suspensions, primary_key: false) do
      add :id, :serial, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :reason, :text
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime  # nil = permanent ban

      timestamps(type: :utc_datetime)
    end

    create index(:account_suspensions, [:account_id])
    create index(:account_suspensions, [:end_time])
  end
end
