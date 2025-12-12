defmodule BezgelorDb.Repo.Migrations.CreateCharacterCurrencies do
  use Ecto.Migration

  def change do
    create table(:character_currencies) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false

      # Primary currencies
      add :gold, :bigint, default: 0, null: false
      add :elder_gems, :integer, default: 0, null: false
      add :renown, :integer, default: 0, null: false
      add :prestige, :integer, default: 0, null: false
      add :glory, :integer, default: 0, null: false

      # Crafting vouchers
      add :crafting_vouchers, :integer, default: 0, null: false

      # PvP currencies
      add :war_coins, :integer, default: 0, null: false

      # Event/seasonal currencies
      add :shade_silver, :integer, default: 0, null: false
      add :protostar_promissory_notes, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_currencies, [:character_id])
  end
end
