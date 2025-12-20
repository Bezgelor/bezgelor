defmodule BezgelorDb.Repo.Migrations.FixClassActionSetDefaults do
  use Ecto.Migration

  def change do
    execute("""
    DELETE FROM character_action_set_shortcuts AS shortcuts
    USING characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class IN (1, 2, 3, 4, 5)
      AND shortcuts.spec_index = 0
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot IN (0, 1, 2, 3)
      AND shortcuts.object_id IN (398, 18309, 24727, 20763, 960, 19102, 26531, 16322, 2656, 23148)
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 18309, 18309, 1, NOW(), NOW()
    FROM characters
    WHERE class = 1
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 20763, 20763, 1, NOW(), NOW()
    FROM characters
    WHERE class = 2
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 19102, 19102, 1, NOW(), NOW()
    FROM characters
    WHERE class = 3
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 16322, 16322, 1, NOW(), NOW()
    FROM characters
    WHERE class = 4
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 23148, 23148, 1, NOW(), NOW()
    FROM characters
    WHERE class = 5
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)

    execute("""
    UPDATE inventory_items AS items
    SET bag_index = CASE items.item_id
      WHEN 18309 THEN 1000
      WHEN 20763 THEN 1000
      WHEN 19102 THEN 1000
      WHEN 16322 THEN 1000
      WHEN 23148 THEN 1000
      WHEN 398 THEN 1003
      WHEN 24727 THEN 1003
      WHEN 960 THEN 1003
      WHEN 26531 THEN 1003
      WHEN 2656 THEN 1003
    END
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class IN (1, 2, 3, 4, 5)
      AND items.container_type = 'ability'
      AND items.slot = 0
      AND items.item_id IN (18309, 20763, 19102, 16322, 23148, 398, 24727, 960, 26531, 2656)
    """)

    execute("""
    UPDATE inventory_items AS items
    SET bag_index = CASE items.item_id
      WHEN 18309 THEN 0
      WHEN 20763 THEN 0
      WHEN 19102 THEN 0
      WHEN 16322 THEN 0
      WHEN 23148 THEN 0
      WHEN 398 THEN 3
      WHEN 24727 THEN 3
      WHEN 960 THEN 3
      WHEN 26531 THEN 3
      WHEN 2656 THEN 3
    END
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class IN (1, 2, 3, 4, 5)
      AND items.container_type = 'ability'
      AND items.slot = 0
      AND items.bag_index IN (1000, 1003)
    """)
  end
end
