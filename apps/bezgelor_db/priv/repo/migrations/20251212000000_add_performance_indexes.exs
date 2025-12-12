defmodule BezgelorDb.Repo.Migrations.AddPerformanceIndexes do
  @moduledoc """
  Add database indexes for frequently-queried columns identified during
  architecture remediation (Issue #2).

  These indexes optimize common query patterns:
  - Work order status lookups and expiration checks
  - Schematic discovery duplicate checks
  - Store promotion filtering by active status and dates
  - Inventory slot lookups by bag
  - Character lookups by account
  """

  use Ecto.Migration

  def change do
    # Work orders - queried by status and expiration for active work order lists
    create_if_not_exists index(:work_orders, [:status, :expires_at],
      name: :work_orders_status_expires_idx
    )

    # Schematic discoveries - queried by schematic_id for duplicate checks
    create_if_not_exists index(:schematic_discoveries, [:schematic_id],
      name: :schematic_discoveries_schematic_idx
    )

    # Store promotions - queried by active status and date ranges
    create_if_not_exists index(:store_promotions, [:is_active, :starts_at, :ends_at],
      name: :store_promotions_active_dates_idx
    )

    # Inventory items - queried by bag_index and slot for slot lookups
    create_if_not_exists index(:inventory_items, [:character_id, :container_type, :bag_index, :slot],
      name: :inventory_items_location_idx
    )

    # Characters - queried by account_id and soft delete status
    create_if_not_exists index(:characters, [:account_id, :deleted_at],
      name: :characters_account_deleted_idx
    )

    # Daily deals - queried by active date
    create_if_not_exists index(:daily_deals, [:active_date],
      name: :daily_deals_active_date_idx
    )

    # Store items - queried by category and active status
    create_if_not_exists index(:store_items, [:category_id, :active],
      name: :store_items_category_active_idx
    )

    # Promo redemptions - queried by promo_code_id and account_id for use checks
    create_if_not_exists index(:promo_redemptions, [:promo_code_id, :account_id],
      name: :promo_redemptions_code_account_idx
    )
  end
end
