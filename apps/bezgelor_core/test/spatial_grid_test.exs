defmodule BezgelorCore.SpatialGridTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.SpatialGrid

  describe "new/1" do
    test "creates empty grid with default cell size" do
      grid = SpatialGrid.new()
      assert grid.cell_size == 50.0
      assert grid.cells == %{}
      assert grid.entity_positions == %{}
    end

    test "creates empty grid with custom cell size" do
      grid = SpatialGrid.new(25.0)
      assert grid.cell_size == 25.0
    end
  end

  describe "insert/3" do
    test "inserts entity at position" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})

      assert SpatialGrid.has_entity?(grid, 1)
      assert SpatialGrid.get_position(grid, 1) == {5.0, 5.0, 0.0}
      assert SpatialGrid.count(grid) == 1
    end

    test "inserts multiple entities" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.insert(2, {15.0, 5.0, 0.0})
        |> SpatialGrid.insert(3, {100.0, 100.0, 0.0})

      assert SpatialGrid.count(grid) == 3
      assert SpatialGrid.has_entity?(grid, 1)
      assert SpatialGrid.has_entity?(grid, 2)
      assert SpatialGrid.has_entity?(grid, 3)
    end

    test "overwrites existing entity position" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.insert(1, {95.0, 95.0, 0.0})

      assert SpatialGrid.count(grid) == 1
      assert SpatialGrid.get_position(grid, 1) == {95.0, 95.0, 0.0}
    end
  end

  describe "remove/2" do
    test "removes entity from grid" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.remove(1)

      refute SpatialGrid.has_entity?(grid, 1)
      assert SpatialGrid.count(grid) == 0
    end

    test "no-op for non-existent entity" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.remove(999)

      assert SpatialGrid.count(grid) == 1
    end

    test "cleans up empty cells" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.remove(1)

      assert grid.cells == %{}
    end
  end

  describe "update/3" do
    test "updates entity position within same cell" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.update(1, {6.0, 6.0, 0.0})

      assert SpatialGrid.get_position(grid, 1) == {6.0, 6.0, 0.0}
      assert SpatialGrid.count(grid) == 1
    end

    test "updates entity position to different cell" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.update(1, {95.0, 95.0, 0.0})

      assert SpatialGrid.get_position(grid, 1) == {95.0, 95.0, 0.0}

      # Should not be in old cell
      old_cell = SpatialGrid.get_cell(grid, {5.0, 5.0, 0.0})
      assert SpatialGrid.entities_in_cell(grid, old_cell) == []

      # Should be in new cell
      new_cell = SpatialGrid.get_cell(grid, {95.0, 95.0, 0.0})
      assert 1 in SpatialGrid.entities_in_cell(grid, new_cell)
    end

    test "inserts if entity doesn't exist" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.update(1, {5.0, 5.0, 0.0})

      assert SpatialGrid.has_entity?(grid, 1)
      assert SpatialGrid.get_position(grid, 1) == {5.0, 5.0, 0.0}
    end
  end

  describe "entities_in_range/3" do
    test "finds entities within range" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.insert(2, {15.0, 5.0, 0.0})
        |> SpatialGrid.insert(3, {100.0, 100.0, 0.0})

      # Entity 1 and 2 are within 20 units of origin
      result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 20.0)
      assert 1 in result
      assert 2 in result
      refute 3 in result
    end

    test "returns empty list when no entities in range" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {100.0, 100.0, 0.0})

      result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 10.0)
      assert result == []
    end

    test "works with empty grid" do
      grid = SpatialGrid.new(10.0)
      result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 100.0)
      assert result == []
    end

    test "handles 3D distance correctly" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {0.0, 0.0, 0.0})
        |> SpatialGrid.insert(2, {0.0, 0.0, 5.0})
        |> SpatialGrid.insert(3, {0.0, 0.0, 15.0})

      # Query from z=10, radius=6 should get entity at z=5 and z=15, but not z=0
      result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 10.0}, 6.0)
      assert 2 in result
      assert 3 in result
      refute 1 in result
    end

    test "handles zero radius" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})

      result = SpatialGrid.entities_in_range(grid, {5.0, 5.0, 0.0}, 0.0)
      assert 1 in result
    end

    test "handles entities exactly at boundary" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {10.0, 0.0, 0.0})

      # Entity at exactly radius distance should be included (<=, not <)
      result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 10.0)
      assert 1 in result
    end
  end

  describe "get_cell/2" do
    test "returns correct cell for position" do
      grid = SpatialGrid.new(10.0)

      assert SpatialGrid.get_cell(grid, {5.0, 5.0, 0.0}) == {0, 0, 0}
      assert SpatialGrid.get_cell(grid, {15.0, 5.0, 0.0}) == {1, 0, 0}
      assert SpatialGrid.get_cell(grid, {-5.0, -5.0, 0.0}) == {-1, -1, 0}
    end

    test "handles cell boundaries" do
      grid = SpatialGrid.new(10.0)

      assert SpatialGrid.get_cell(grid, {0.0, 0.0, 0.0}) == {0, 0, 0}
      assert SpatialGrid.get_cell(grid, {10.0, 0.0, 0.0}) == {1, 0, 0}
      assert SpatialGrid.get_cell(grid, {9.999, 0.0, 0.0}) == {0, 0, 0}
    end
  end

  describe "all_guids/1" do
    test "returns all entity guids" do
      grid =
        SpatialGrid.new(10.0)
        |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
        |> SpatialGrid.insert(2, {15.0, 5.0, 0.0})
        |> SpatialGrid.insert(3, {100.0, 100.0, 0.0})

      guids = SpatialGrid.all_guids(grid)
      assert length(guids) == 3
      assert 1 in guids
      assert 2 in guids
      assert 3 in guids
    end
  end

  describe "performance characteristics" do
    test "handles large number of entities" do
      # Insert 1000 entities spread across the world
      grid =
        Enum.reduce(1..1000, SpatialGrid.new(50.0), fn i, grid ->
          x = :rand.uniform() * 10000
          y = :rand.uniform() * 10000
          z = :rand.uniform() * 100
          SpatialGrid.insert(grid, i, {x, y, z})
        end)

      assert SpatialGrid.count(grid) == 1000

      # Range query should still be fast (only checks nearby cells)
      result = SpatialGrid.entities_in_range(grid, {5000.0, 5000.0, 50.0}, 100.0)
      assert is_list(result)
    end

    test "clustered entities in same cell" do
      # Insert 100 entities in the same area
      grid =
        Enum.reduce(1..100, SpatialGrid.new(50.0), fn i, grid ->
          x = 25.0 + :rand.uniform() * 10
          y = 25.0 + :rand.uniform() * 10
          SpatialGrid.insert(grid, i, {x, y, 0.0})
        end)

      assert SpatialGrid.count(grid) == 100

      # All should be findable
      result = SpatialGrid.entities_in_range(grid, {25.0, 25.0, 0.0}, 50.0)
      assert length(result) == 100
    end
  end
end
