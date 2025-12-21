defmodule BezgelorDb.Repo.Migrations.AddActionSetShortcutColumns do
  use Ecto.Migration

  def change do
    execute("""
    ALTER TABLE character_action_set_shortcuts
    ADD COLUMN IF NOT EXISTS shortcut_type integer NOT NULL DEFAULT 0
    """)

    execute("""
    ALTER TABLE character_action_set_shortcuts
    ADD COLUMN IF NOT EXISTS object_id integer NOT NULL DEFAULT 0
    """)

    execute("""
    ALTER TABLE character_action_set_shortcuts
    ADD COLUMN IF NOT EXISTS tier integer NOT NULL DEFAULT 1
    """)

    create_if_not_exists(
      index(:character_action_set_shortcuts, [:character_id, :spec_index, :object_id])
    )
  end
end
