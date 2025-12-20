defmodule BezgelorDb.Repo.Migrations.FixSpellslingerLasBaseIds do
  use Ecto.Migration

  def change do
    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 27638,
        spell_id = 27638
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 1
      AND shortcuts.object_id IN (43468, 27638)
    """)

    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 20684,
        spell_id = 20684
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 2
      AND shortcuts.object_id IN (43278, 27456, 20684)
    """)

    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 20325,
        spell_id = 20325
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 3
      AND shortcuts.object_id IN (43283, 27461, 20325)
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 27638
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 1
      AND items.item_id IN (43468, 27638)
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 20684
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 2
      AND items.item_id IN (43278, 27456, 20684)
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 20325
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 3
      AND items.item_id IN (43283, 27461, 20325)
    """)
  end
end
