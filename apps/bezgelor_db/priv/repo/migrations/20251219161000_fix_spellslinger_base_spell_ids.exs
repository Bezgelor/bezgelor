defmodule BezgelorDb.Repo.Migrations.FixSpellslingerBaseSpellIds do
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
      AND shortcuts.object_id = 43468
    """)

    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 27456,
        spell_id = 27456
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 2
      AND shortcuts.object_id = 43278
    """)

    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 27461,
        spell_id = 27461
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 3
      AND shortcuts.object_id = 43283
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 27638
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 1
      AND items.item_id = 43468
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 27456
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 2
      AND items.item_id = 43278
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 27461
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 3
      AND items.item_id = 43283
    """)
  end
end
