defmodule BezgelorDb.Repo.Migrations.FixSpellslingerDefaultShortcuts do
  use Ecto.Migration

  def change do
    execute("""
    UPDATE character_action_set_shortcuts AS shortcuts
    SET object_id = 43468,
        spell_id = 43468
    FROM characters
    WHERE shortcuts.character_id = characters.id
      AND characters.class = 7
      AND shortcuts.shortcut_type = 4
      AND shortcuts.slot = 1
      AND shortcuts.object_id = 27638
    """)

    execute("""
    UPDATE inventory_items AS items
    SET item_id = 43468
    FROM characters
    WHERE items.character_id = characters.id
      AND characters.class = 7
      AND items.container_type = 'ability'
      AND items.bag_index = 1
      AND items.item_id = 27638
    """)
  end
end
