defmodule BezgelorDb.Repo.Migrations.CreateActionSetShortcuts do
  use Ecto.Migration

  def change do
    create table(:character_action_set_shortcuts) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :spec_index, :integer, null: false
      add :slot, :integer, null: false
      add :shortcut_type, :integer, null: false
      add :object_id, :integer, null: false
      add :tier, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:character_action_set_shortcuts, [:character_id, :spec_index])
    create index(:character_action_set_shortcuts, [:character_id, :spec_index, :object_id])

    create unique_index(
             :character_action_set_shortcuts,
             [:character_id, :spec_index, :slot],
             name: :character_action_set_shortcuts_slot_index
           )
  end
end
