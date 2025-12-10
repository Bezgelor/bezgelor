defmodule BezgelorDb.Repo.Migrations.CreateStorefront do
  use Ecto.Migration

  def change do
    create table(:store_items) do
      add :item_type, :string, null: false  # "mount", "pet", "costume", "dye", "service"
      add :item_id, :integer, null: false   # Reference to actual item (mount_id, pet_id, etc.)
      add :name, :string, null: false
      add :description, :text
      add :premium_price, :integer          # Price in premium currency (NCoin)
      add :bonus_price, :integer            # Price in bonus currency (Omnibits)
      add :gold_price, :bigint              # Price in gold (for some items)
      add :category, :string                # UI category for filtering
      add :featured, :boolean, default: false
      add :limited_time, :boolean, default: false
      add :available_from, :utc_datetime
      add :available_until, :utc_datetime
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:store_items, [:item_type])
    create index(:store_items, [:category])
    create index(:store_items, [:active])
    create unique_index(:store_items, [:item_type, :item_id])

    create table(:store_purchases) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :store_item_id, references(:store_items, on_delete: :restrict), null: false
      add :currency_type, :string, null: false  # "premium", "bonus", "gold"
      add :amount_paid, :bigint, null: false
      add :character_id, :integer  # Optional: if purchased for specific character

      timestamps(type: :utc_datetime)
    end

    create index(:store_purchases, [:account_id])
    create index(:store_purchases, [:store_item_id])
  end
end
