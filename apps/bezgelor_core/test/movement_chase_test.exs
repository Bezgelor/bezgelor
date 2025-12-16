defmodule BezgelorCore.MovementChaseTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Movement

  describe "chase_path/3" do
    test "generates path toward target stopping at attack range" do
      current = {0.0, 0.0, 0.0}
      target = {20.0, 0.0, 0.0}
      attack_range = 5.0

      path = Movement.chase_path(current, target, attack_range)

      # Path should end at attack range from target
      {end_x, _, _} = List.last(path)
      assert_in_delta end_x, 15.0, 0.5  # 20 - 5 = 15
    end

    test "returns empty path if already in range" do
      current = {3.0, 0.0, 0.0}
      target = {5.0, 0.0, 0.0}
      attack_range = 5.0

      path = Movement.chase_path(current, target, attack_range)

      assert path == []
    end

    test "path has waypoints every 2 units" do
      current = {0.0, 0.0, 0.0}
      target = {10.0, 0.0, 0.0}
      attack_range = 2.0

      path = Movement.chase_path(current, target, attack_range)

      # Should have ~4 waypoints for 8 unit travel
      assert length(path) >= 3
      assert length(path) <= 5
    end
  end

  describe "ranged_position_path/4" do
    test "moves closer when too far from target" do
      current = {0.0, 0.0, 0.0}
      target = {50.0, 0.0, 0.0}  # 50 units away
      min_range = 15.0
      max_range = 30.0

      path = Movement.ranged_position_path(current, target, min_range, max_range)

      # Should move to optimal distance: (15 + 30) / 2 = 22.5 from target
      # So end at 50 - 22.5 = 27.5 from origin
      {end_x, _, _} = List.last(path)
      assert_in_delta end_x, 27.5, 2.0
    end

    test "backs away when too close to target" do
      current = {25.0, 0.0, 0.0}  # 5 units from target
      target = {30.0, 0.0, 0.0}
      min_range = 15.0
      max_range = 25.0

      path = Movement.ranged_position_path(current, target, min_range, max_range)

      # Should move backwards to increase distance
      {end_x, _, _} = List.last(path)
      # Must be at least min_range away from target (30)
      assert end_x <= 30.0 - 15.0  # At most 15.0
    end

    test "returns empty path when in optimal range" do
      current = {10.0, 0.0, 0.0}  # 20 units from target
      target = {30.0, 0.0, 0.0}
      min_range = 15.0
      max_range = 25.0

      path = Movement.ranged_position_path(current, target, min_range, max_range)

      # Already in range (20 is between 15 and 25)
      assert path == []
    end
  end

  describe "rotation_toward/2" do
    test "calculates rotation to face positive X direction" do
      current = {0.0, 0.0, 0.0}
      target = {10.0, 0.0, 0.0}

      rotation = Movement.rotation_toward(current, target)

      # Facing +X should be PI/2 radians (90 degrees)
      assert_in_delta rotation, :math.pi() / 2, 0.01
    end

    test "calculates rotation to face positive Z direction" do
      current = {0.0, 0.0, 0.0}
      target = {0.0, 0.0, 10.0}

      rotation = Movement.rotation_toward(current, target)

      # Facing +Z should be 0 radians
      assert_in_delta rotation, 0.0, 0.01
    end

    test "calculates rotation to face negative X direction" do
      current = {0.0, 0.0, 0.0}
      target = {-10.0, 0.0, 0.0}

      rotation = Movement.rotation_toward(current, target)

      # Facing -X should be -PI/2 radians (-90 degrees)
      assert_in_delta rotation, -:math.pi() / 2, 0.01
    end

    test "ignores Y coordinate difference" do
      current = {0.0, 0.0, 0.0}
      target = {10.0, 100.0, 0.0}  # Large Y difference

      rotation = Movement.rotation_toward(current, target)

      # Should still face +X direction
      assert_in_delta rotation, :math.pi() / 2, 0.01
    end
  end
end
