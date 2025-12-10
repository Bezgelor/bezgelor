defmodule BezgelorDb.Repo.Migrations.CreateAccountCurrencies do
  use Ecto.Migration

  def change do
    create table(:account_currencies) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :premium_currency, :integer, default: 0
      add :bonus_currency, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_currencies, [:account_id])
  end
end
