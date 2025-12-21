defmodule BezgelorDb.Repo.Migrations.AddSpellIdToActionSetShortcuts do
  use Ecto.Migration

  def change do
    execute("""
    ALTER TABLE character_action_set_shortcuts
    ADD COLUMN IF NOT EXISTS spell_id integer NOT NULL DEFAULT 0
    """)

    execute("""
    UPDATE character_action_set_shortcuts
    SET spell_id = object_id
    WHERE spell_id IS NULL OR spell_id = 0
    """)
  end
end
