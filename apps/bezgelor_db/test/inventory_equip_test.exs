defmodule BezgelorDb.InventoryEquipTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Inventory

  describe "can_equip_in_slot?/2" do
    test "returns false for unknown item" do
      refute Inventory.can_equip_in_slot?(999_999_999, 1)
    end

    # Note: Full testing requires game data to be loaded in ETS.
    # These tests verify the API works without actual data.
    test "returns false when Store returns nil" do
      # Item ID 0 should not exist
      refute Inventory.can_equip_in_slot?(0, 1)
    end
  end

  describe "validate_equip_slot/3" do
    # This is a private function, so we test it indirectly through move_item
    # The actual validation behavior is tested in integration tests
    # that have game data loaded.
  end
end
