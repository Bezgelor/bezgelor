defmodule BezgelorDb.Repo.Migrations.CreateCurrencyTransactions do
  use Ecto.Migration

  def change do
    # Currency transactions - audit trail for all currency changes
    create table(:currency_transactions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :currency_type, :integer, null: false
      add :amount, :integer, null: false
      add :balance_after, :integer, null: false
      add :source_type, :string, null: false
      add :source_id, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:currency_transactions, [:character_id])
    create index(:currency_transactions, [:character_id, :currency_type])
    create index(:currency_transactions, [:source_type])
    create index(:currency_transactions, [:inserted_at])
  end
end
