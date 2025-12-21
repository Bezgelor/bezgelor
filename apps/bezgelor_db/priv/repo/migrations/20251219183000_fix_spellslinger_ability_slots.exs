defmodule BezgelorDb.Repo.Migrations.FixSpellslingerAbilitySlots do
  use Ecto.Migration

  def change do
    execute("""
    UPDATE inventory_items AS items
    SET bag_index = CASE items.item_id
      WHEN 27638 THEN 1000
      WHEN 20684 THEN 1001
      WHEN 20325 THEN 1002
      WHEN 435 THEN 1003
    END
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.slot = 0
      AND items.item_id IN (27638, 20684, 20325, 435)
    """)

    execute("""
    UPDATE inventory_items AS items
    SET bag_index = CASE items.item_id
      WHEN 27638 THEN 0
      WHEN 20684 THEN 1
      WHEN 20325 THEN 2
      WHEN 435 THEN 3
    END
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.slot = 0
      AND items.bag_index IN (1000, 1001, 1002, 1003)
    """)
  end
end
