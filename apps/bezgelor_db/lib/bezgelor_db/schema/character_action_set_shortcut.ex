defmodule BezgelorDb.Schema.CharacterActionSetShortcut do
  @moduledoc """
  Schema for persisted Limited Action Set shortcuts.

  Each shortcut maps a spell to a UI slot within a spec's action set.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "character_action_set_shortcuts" do
    belongs_to(:character, BezgelorDb.Schema.Character)

    field(:spec_index, :integer)
    field(:slot, :integer)
    field(:shortcut_type, :integer)
    field(:object_id, :integer)
    field(:spell_id, :integer)
    field(:tier, :integer, default: 1)

    timestamps(type: :utc_datetime)
  end

  def changeset(shortcut, attrs) do
    shortcut
    |> cast(attrs, [
      :character_id,
      :spec_index,
      :slot,
      :shortcut_type,
      :object_id,
      :spell_id,
      :tier
    ])
    |> validate_required([
      :character_id,
      :spec_index,
      :slot,
      :shortcut_type,
      :object_id,
      :spell_id,
      :tier
    ])
    |> validate_number(:spec_index, greater_than_or_equal_to: 0, less_than: 4)
    |> validate_number(:slot, greater_than_or_equal_to: 0)
    |> validate_number(:tier, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :spec_index, :slot],
      name: :character_action_set_shortcuts_slot_index
    )
  end
end
