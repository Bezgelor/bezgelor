defmodule BezgelorDb.Repo.Migrations.CreateInventoryTables do
  use Ecto.Migration

  def change do
    # Bags table
    create table(:bags) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :bag_index, :integer, null: false
      add :item_id, :integer  # nil for backpack
      add :size, :integer, null: false, default: 12

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bags, [:character_id, :bag_index])

    # Inventory items table
    create table(:inventory_items) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :item_id, :integer, null: false

      # Location
      add :container_type, :string, null: false, default: "bag"
      add :bag_index, :integer, null: false, default: 0
      add :slot, :integer, null: false

      # Stack info
      add :quantity, :integer, null: false, default: 1
      add :max_stack, :integer, null: false, default: 1

      # Item state
      add :durability, :integer, default: 100
      add :max_durability, :integer, default: 100
      add :bound, :boolean, default: false

      # Random properties
      add :random_seed, :integer
      add :enchant_id, :integer
      add :gem_ids, {:array, :integer}, default: []

      # Charges
      add :charges, :integer

      timestamps(type: :utc_datetime)
    end

    # Unique constraint on item location
    create unique_index(:inventory_items, [:character_id, :container_type, :bag_index, :slot],
           name: :inventory_items_location_index)

    # Index for finding all items for a character
    create index(:inventory_items, [:character_id])

    # Index for finding items by item_id (for stacking)
    create index(:inventory_items, [:character_id, :item_id])
  end
end
