defmodule BezgelorWorld.Crafting.CoordinateSystemTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Crafting.CoordinateSystem

  describe "find_target_zone/3" do
    setup do
      zones = [
        %{id: 1, x_min: 0, x_max: 30, y_min: 0, y_max: 30, variant_id: 0, quality: :poor},
        %{id: 2, x_min: 40, x_max: 60, y_min: 40, y_max: 60, variant_id: 0, quality: :standard},
        %{id: 3, x_min: 70, x_max: 90, y_min: 70, y_max: 90, variant_id: 101, quality: :exceptional}
      ]
      {:ok, zones: zones}
    end

    test "returns zone when cursor is inside", %{zones: zones} do
      assert {:ok, zone} = CoordinateSystem.find_target_zone(50.0, 50.0, zones)
      assert zone.id == 2
      assert zone.quality == :standard
    end

    test "returns first matching zone for overlapping areas", %{zones: zones} do
      # Edge case: exactly on boundary
      assert {:ok, zone} = CoordinateSystem.find_target_zone(40.0, 40.0, zones)
      assert zone.id == 2
    end

    test "returns :no_zone when outside all zones", %{zones: zones} do
      assert :no_zone = CoordinateSystem.find_target_zone(35.0, 35.0, zones)
    end

    test "handles negative coordinates", %{zones: zones} do
      assert :no_zone = CoordinateSystem.find_target_zone(-10.0, -10.0, zones)
    end
  end

  describe "apply_additive/3" do
    test "moves cursor by additive vector" do
      cursor = {10.0, 20.0}
      additive = %{vector_x: 5.0, vector_y: -3.0}

      assert {15.0, 17.0} = CoordinateSystem.apply_additive(cursor, additive, 0)
    end

    test "applies overcharge multiplier" do
      cursor = {10.0, 20.0}
      additive = %{vector_x: 5.0, vector_y: -3.0}

      # Overcharge level 2 = 1.5x multiplier
      {new_x, new_y} = CoordinateSystem.apply_additive(cursor, additive, 2)
      assert_in_delta new_x, 17.5, 0.001
      assert_in_delta new_y, 15.5, 0.001
    end

    test "overcharge level 0 means no amplification" do
      cursor = {0.0, 0.0}
      additive = %{vector_x: 10.0, vector_y: 10.0}

      assert {10.0, 10.0} = CoordinateSystem.apply_additive(cursor, additive, 0)
    end
  end

  describe "calculate_overcharge_multiplier/1" do
    test "level 0 returns 1.0" do
      assert CoordinateSystem.calculate_overcharge_multiplier(0) == 1.0
    end

    test "level 1 returns 1.25" do
      assert CoordinateSystem.calculate_overcharge_multiplier(1) == 1.25
    end

    test "level 2 returns 1.5" do
      assert CoordinateSystem.calculate_overcharge_multiplier(2) == 1.5
    end

    test "level 3 returns 2.0" do
      assert CoordinateSystem.calculate_overcharge_multiplier(3) == 2.0
    end
  end

  describe "calculate_failure_chance/1" do
    test "level 0 has 0% failure" do
      assert CoordinateSystem.calculate_failure_chance(0) == 0.0
    end

    test "level 1 has 10% failure" do
      assert CoordinateSystem.calculate_failure_chance(1) == 0.10
    end

    test "level 2 has 25% failure" do
      assert CoordinateSystem.calculate_failure_chance(2) == 0.25
    end

    test "level 3 has 50% failure" do
      assert CoordinateSystem.calculate_failure_chance(3) == 0.50
    end
  end
end
