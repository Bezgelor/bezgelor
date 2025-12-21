defmodule BezgelorDb.Repo.Migrations.SyncClassActionSetDefaults do
  use Ecto.Migration

  def change do
    execute("""
    DELETE FROM inventory_items AS dup
    USING inventory_items AS keep, characters
    WHERE dup.character_id = keep.character_id
      AND dup.container_type = 'ability'
      AND keep.container_type = 'ability'
      AND dup.slot = 0
      AND keep.slot = 0
      AND dup.bag_index = keep.bag_index
      AND dup.id > keep.id
      AND dup.character_id = characters.id
      AND characters.class IN (1, 2, 3, 4, 5, 7)
      AND dup.bag_index IN (0, 1, 2, 3)
    """)

    execute("""
    WITH defaults AS (
      SELECT 1 AS class_id, 0 AS slot, 32078 AS spell_id UNION ALL
      SELECT 1, 1, 58524 UNION ALL
      SELECT 1, 2, 58591 UNION ALL
      SELECT 2, 0, 42276 UNION ALL
      SELECT 2, 1, 41276 UNION ALL
      SELECT 2, 2, 41438 UNION ALL
      SELECT 3, 0, 32893 UNION ALL
      SELECT 3, 1, 32809 UNION ALL
      SELECT 3, 2, 32812 UNION ALL
      SELECT 4, 0, 58832 UNION ALL
      SELECT 4, 1, 29874 UNION ALL
      SELECT 4, 2, 42352 UNION ALL
      SELECT 5, 0, 38765 UNION ALL
      SELECT 5, 1, 38779 UNION ALL
      SELECT 5, 2, 38791 UNION ALL
      SELECT 7, 0, 43468 UNION ALL
      SELECT 7, 1, 34718 UNION ALL
      SELECT 7, 2, 34355
    )
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT characters.id, 0, defaults.slot, 4, defaults.spell_id, defaults.spell_id, 1, NOW(), NOW()
    FROM characters
    JOIN defaults ON defaults.class_id = characters.class
    ON CONFLICT (character_id, spec_index, slot)
    DO NOTHING
    """)

    execute("""
    WITH defaults AS (
      SELECT 1 AS class_id, 0 AS slot, 32078 AS spell_id UNION ALL
      SELECT 1, 1, 58524 UNION ALL
      SELECT 1, 2, 58591 UNION ALL
      SELECT 2, 0, 42276 UNION ALL
      SELECT 2, 1, 41276 UNION ALL
      SELECT 2, 2, 41438 UNION ALL
      SELECT 3, 0, 32893 UNION ALL
      SELECT 3, 1, 32809 UNION ALL
      SELECT 3, 2, 32812 UNION ALL
      SELECT 4, 0, 58832 UNION ALL
      SELECT 4, 1, 29874 UNION ALL
      SELECT 4, 2, 42352 UNION ALL
      SELECT 5, 0, 38765 UNION ALL
      SELECT 5, 1, 38779 UNION ALL
      SELECT 5, 2, 38791 UNION ALL
      SELECT 7, 0, 43468 UNION ALL
      SELECT 7, 1, 34718 UNION ALL
      SELECT 7, 2, 34355
    )
    UPDATE character_action_set_shortcuts AS shortcuts
    SET shortcut_type = 4,
        object_id = defaults.spell_id,
        spell_id = defaults.spell_id,
        tier = 1,
        updated_at = NOW()
    FROM characters
    JOIN defaults ON defaults.class_id = characters.class
    WHERE shortcuts.character_id = characters.id
      AND shortcuts.spec_index = 0
      AND shortcuts.slot = defaults.slot
      AND (shortcuts.shortcut_type = 0 OR shortcuts.object_id = 0)
    """)

    execute("""
    WITH inventory_defaults AS (
      SELECT 1 AS class_id, 0 AS bag_index, 32078 AS spell_id UNION ALL
      SELECT 1, 1, 58524 UNION ALL
      SELECT 1, 2, 58591 UNION ALL
      SELECT 1, 3, 55543 UNION ALL
      SELECT 2, 0, 42276 UNION ALL
      SELECT 2, 1, 41276 UNION ALL
      SELECT 2, 2, 41438 UNION ALL
      SELECT 2, 3, 40510 UNION ALL
      SELECT 3, 0, 32893 UNION ALL
      SELECT 3, 1, 32809 UNION ALL
      SELECT 3, 2, 32812 UNION ALL
      SELECT 3, 3, 960 UNION ALL
      SELECT 4, 0, 58832 UNION ALL
      SELECT 4, 1, 29874 UNION ALL
      SELECT 4, 2, 42352 UNION ALL
      SELECT 4, 3, 55533 UNION ALL
      SELECT 5, 0, 38765 UNION ALL
      SELECT 5, 1, 38779 UNION ALL
      SELECT 5, 2, 38791 UNION ALL
      SELECT 5, 3, 55198 UNION ALL
      SELECT 7, 0, 43468 UNION ALL
      SELECT 7, 1, 34718 UNION ALL
      SELECT 7, 2, 34355 UNION ALL
      SELECT 7, 3, 55665
    )
    INSERT INTO inventory_items
      (character_id, item_id, container_type, bag_index, slot, quantity, max_stack, durability, max_durability,
       inserted_at, updated_at)
    SELECT characters.id,
           inventory_defaults.spell_id,
           'ability',
           inventory_defaults.bag_index,
           0,
           1,
           1,
           100,
           100,
           NOW(),
           NOW()
    FROM characters
    JOIN inventory_defaults ON inventory_defaults.class_id = characters.class
    ON CONFLICT (character_id, container_type, bag_index, slot)
    DO UPDATE SET
      item_id = EXCLUDED.item_id,
      quantity = EXCLUDED.quantity,
      max_stack = EXCLUDED.max_stack,
      durability = EXCLUDED.durability,
      max_durability = EXCLUDED.max_durability,
      updated_at = EXCLUDED.updated_at
    """)
  end
end
