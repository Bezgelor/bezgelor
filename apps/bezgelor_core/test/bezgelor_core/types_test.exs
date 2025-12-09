defmodule BezgelorCore.TypesTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Types.Vector3

  describe "Vector3" do
    test "creates a vector with x, y, z coordinates" do
      vec = %Vector3{x: 1.0, y: 2.0, z: 3.0}
      assert vec.x == 1.0
      assert vec.y == 2.0
      assert vec.z == 3.0
    end

    test "defaults to origin (0, 0, 0)" do
      vec = %Vector3{}
      assert vec.x == 0.0
      assert vec.y == 0.0
      assert vec.z == 0.0
    end

    test "calculates distance between two vectors" do
      v1 = %Vector3{x: 0.0, y: 0.0, z: 0.0}
      v2 = %Vector3{x: 3.0, y: 4.0, z: 0.0}
      assert Vector3.distance(v1, v2) == 5.0
    end
  end
end
