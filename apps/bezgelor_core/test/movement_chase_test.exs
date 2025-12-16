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
end
