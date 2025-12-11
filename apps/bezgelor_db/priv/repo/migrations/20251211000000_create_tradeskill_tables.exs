defmodule BezgelorDb.Repo.Migrations.CreateTradeskillTables do
  use Ecto.Migration

  def change do
    # Profession type enum
    execute(
      "CREATE TYPE profession_type AS ENUM ('crafting', 'gathering')",
      "DROP TYPE profession_type"
    )

    # Work order status enum
    execute(
      "CREATE TYPE work_order_status AS ENUM ('active', 'completed', 'expired')",
      "DROP TYPE work_order_status"
    )

    # Character tradeskill progress
    create table(:character_tradeskills) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :profession_id, :integer, null: false
      add :profession_type, :profession_type, null: false
      add :skill_level, :integer, null: false, default: 0
      add :skill_xp, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:character_tradeskills, [:character_id])
    create unique_index(:character_tradeskills, [:character_id, :profession_id])

    # Schematic discovery - supports both character and account scope
    create table(:schematic_discoveries) do
      add :character_id, references(:characters, on_delete: :delete_all)
      add :account_id, :integer  # For account-wide discovery mode
      add :schematic_id, :integer, null: false
      add :variant_id, :integer, null: false, default: 0
      add :discovered_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime)
    end

    create index(:schematic_discoveries, [:character_id])
    create index(:schematic_discoveries, [:account_id])
    create unique_index(:schematic_discoveries, [:character_id, :schematic_id, :variant_id],
      where: "character_id IS NOT NULL",
      name: :schematic_discoveries_character_unique)
    create unique_index(:schematic_discoveries, [:account_id, :schematic_id, :variant_id],
      where: "account_id IS NOT NULL",
      name: :schematic_discoveries_account_unique)

    # Tradeskill talent allocation
    create table(:tradeskill_talents) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :profession_id, :integer, null: false
      add :talent_id, :integer, null: false
      add :points_spent, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:tradeskill_talents, [:character_id])
    create unique_index(:tradeskill_talents, [:character_id, :profession_id, :talent_id])

    # Work orders
    create table(:work_orders) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :work_order_id, :integer, null: false
      add :profession_id, :integer, null: false
      add :quantity_required, :integer, null: false
      add :quantity_completed, :integer, null: false, default: 0
      add :status, :work_order_status, null: false, default: "active"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime)
    end

    create index(:work_orders, [:character_id])
    create index(:work_orders, [:character_id, :status])
  end
end
