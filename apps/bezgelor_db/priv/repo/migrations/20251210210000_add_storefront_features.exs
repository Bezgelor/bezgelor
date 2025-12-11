defmodule BezgelorDb.Repo.Migrations.AddStorefrontFeatures do
  use Ecto.Migration

  def change do
    # Store categories (hierarchical)
    create table(:store_categories) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :parent_id, references(:store_categories, on_delete: :nilify_all)
      add :sort_order, :integer, default: 0
      add :icon, :string
      add :is_active, :boolean, default: true

      timestamps()
    end

    create unique_index(:store_categories, [:slug])
    create index(:store_categories, [:parent_id])
    create index(:store_categories, [:is_active])

    # Add category reference to store_items
    # Note: featured already exists from original migration
    alter table(:store_items) do
      add :category_id, references(:store_categories, on_delete: :nilify_all)
      add :sort_order, :integer, default: 0
      add :new_until, :utc_datetime
      add :sale_price, :integer
      add :sale_ends_at, :utc_datetime
      add :metadata, :map, default: %{}
    end

    create index(:store_items, [:category_id])

    # Store promotions (time-limited sales, bundles)
    create table(:store_promotions) do
      add :name, :string, null: false
      add :description, :text
      add :promotion_type, :string, null: false  # "sale", "bundle", "bonus_currency"
      add :discount_percent, :integer  # For sales
      add :discount_amount, :integer   # Fixed discount
      add :bonus_amount, :integer      # For bonus currency promotions
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :is_active, :boolean, default: true
      add :banner_image, :string
      add :applies_to, :map, default: %{}  # category_ids, item_ids, etc.

      timestamps()
    end

    create index(:store_promotions, [:promotion_type])
    create index(:store_promotions, [:starts_at, :ends_at])
    create index(:store_promotions, [:is_active])

    # Daily deals (rotating featured items)
    create table(:daily_deals) do
      add :store_item_id, references(:store_items, on_delete: :delete_all), null: false
      add :discount_percent, :integer, null: false
      add :active_date, :date, null: false
      add :quantity_limit, :integer  # Optional max purchases
      add :quantity_sold, :integer, default: 0

      timestamps()
    end

    create unique_index(:daily_deals, [:active_date, :store_item_id])
    create index(:daily_deals, [:active_date])

    # Promo codes
    create table(:promo_codes) do
      add :code, :string, null: false
      add :description, :text
      add :code_type, :string, null: false  # "discount", "item", "currency"
      add :discount_percent, :integer
      add :discount_amount, :integer
      add :granted_item_id, :integer  # For item grants
      add :granted_currency_amount, :integer
      add :granted_currency_type, :string  # "premium", "bonus"
      add :max_uses, :integer  # Total uses allowed (nil = unlimited)
      add :uses_per_account, :integer, default: 1
      add :current_uses, :integer, default: 0
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :is_active, :boolean, default: true
      add :min_purchase_amount, :integer  # Minimum cart value
      add :applies_to, :map, default: %{}  # Restrictions

      timestamps()
    end

    create unique_index(:promo_codes, [:code])
    create index(:promo_codes, [:is_active])
    create index(:promo_codes, [:code_type])

    # Promo code redemptions (track per-account usage)
    create table(:promo_redemptions) do
      add :promo_code_id, references(:promo_codes, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :purchase_id, references(:store_purchases, on_delete: :nilify_all)
      add :redeemed_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:promo_redemptions, [:promo_code_id])
    create index(:promo_redemptions, [:account_id])
    create unique_index(:promo_redemptions, [:promo_code_id, :account_id, :redeemed_at])

    # Enhanced purchase history (extends store_purchases)
    alter table(:store_purchases) do
      add :promo_code_id, references(:promo_codes, on_delete: :nilify_all)
      add :original_price, :integer
      add :discount_applied, :integer, default: 0
      add :promotion_id, references(:store_promotions, on_delete: :nilify_all)
      add :daily_deal_id, references(:daily_deals, on_delete: :nilify_all)
      add :metadata, :map, default: %{}
    end

    create index(:store_purchases, [:promo_code_id])
    create index(:store_purchases, [:promotion_id])
  end
end
