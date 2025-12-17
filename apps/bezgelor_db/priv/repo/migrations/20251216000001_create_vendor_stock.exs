defmodule BezgelorDb.Repo.Migrations.CreateVendorStock do
  use Ecto.Migration

  def change do
    # Track limited stock items for vendors (items with quantity != -1)
    # Most vendor items are unlimited and handled by static game data
    create table(:vendor_stock) do
      add :vendor_id, :integer, null: false
      add :item_id, :integer, null: false
      add :quantity_remaining, :integer, null: false
      add :last_restock_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vendor_stock, [:vendor_id, :item_id])
    create index(:vendor_stock, [:vendor_id])
  end
end
