defmodule BezgelorDb.Repo.Migrations.AddGearMaskToCharacters do
  @moduledoc """
  Add gear_mask column to characters table.

  The gear_mask is a bitmask that controls which equipped gear slots
  are visible on the character. Each bit represents a slot:
  - Bit 0 (1): ArmorChest (slot 1)
  - Bit 1 (2): ArmorLegs (slot 2)
  - Bit 2 (4): ArmorHead (slot 3)
  - Bit 3 (8): ArmorShoulder (slot 4)
  - Bit 4 (16): ArmorFeet (slot 5)
  - Bit 5 (32): ArmorHands (slot 6)
  - etc.

  A set bit means the slot is VISIBLE.
  0xFFFFFFFF = all visible, 0 = all hidden.
  Note: Migration uses 0 default but code treats 0 as "all visible" for compatibility.
  """
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # Bitmask for gear visibility (set bit = visible)
      # Code treats 0 as 0xFFFFFFFF for backward compatibility
      add :gear_mask, :integer, default: 0, null: false
    end
  end
end
