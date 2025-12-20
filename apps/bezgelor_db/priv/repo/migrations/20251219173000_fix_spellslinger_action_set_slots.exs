defmodule BezgelorDb.Repo.Migrations.FixSpellslingerActionSetSlots do
  use Ecto.Migration

  def change do
    execute("""
    DELETE FROM character_action_set_shortcuts AS shortcuts
    USING characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.spec_index = 0
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot IN (0, 1, 2, 3)
      AND shortcuts.object_id IN (435, 27638, 20684, 20325)
    """)

    execute("""
    INSERT INTO character_action_set_shortcuts
      (character_id, spec_index, slot, shortcut_type, object_id, spell_id, tier, inserted_at, updated_at)
    SELECT id, 0, 0, 4, 27638, 27638, 1, NOW(), NOW()
    FROM characters
    WHERE class = 7
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
    SELECT id, 0, 1, 4, 20684, 20684, 1, NOW(), NOW()
    FROM characters
    WHERE class = 7
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
    SELECT id, 0, 2, 4, 20325, 20325, 1, NOW(), NOW()
    FROM characters
    WHERE class = 7
    ON CONFLICT (character_id, spec_index, slot)
    DO UPDATE SET
      shortcut_type = EXCLUDED.shortcut_type,
      object_id = EXCLUDED.object_id,
      spell_id = EXCLUDED.spell_id,
      tier = EXCLUDED.tier,
      updated_at = EXCLUDED.updated_at
    """)
  end
end
