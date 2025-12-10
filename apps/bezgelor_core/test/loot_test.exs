defmodule BezgelorCore.LootTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Loot

  describe "get/1" do
    test "returns loot table by ID" do
      table = Loot.get(1)

      assert %Loot{} = table
      assert table.id == 1
      assert length(table.entries) > 0
    end

    test "returns nil for unknown ID" do
      assert nil == Loot.get(999)
    end
  end

  describe "exists?/1" do
    test "returns true for known tables" do
      assert Loot.exists?(1)
      assert Loot.exists?(2)
    end

    test "returns false for unknown tables" do
      refute Loot.exists?(999)
    end
  end

  describe "roll/1" do
    test "returns list of drops" do
      # Run multiple times due to randomness
      results =
        for _ <- 1..100 do
          Loot.roll(1)
        end

      # All results should be lists
      assert Enum.all?(results, &is_list/1)

      # At least some should have drops (100% gold)
      assert Enum.any?(results, fn drops -> length(drops) > 0 end)
    end

    test "drops are {item_id, quantity} tuples" do
      # Table 3 always drops gold
      drops = Loot.roll(3)

      assert length(drops) >= 1

      for {item_id, quantity} <- drops do
        assert is_integer(item_id)
        assert is_integer(quantity)
        assert quantity >= 1
      end
    end

    test "returns empty list for unknown table" do
      assert [] == Loot.roll(999)
    end

    test "respects quantity ranges" do
      # Table 1 gold drops 1-5
      for _ <- 1..100 do
        drops = Loot.roll(1)
        gold_drops = Enum.filter(drops, fn {id, _} -> id == 0 end)

        for {_, quantity} <- gold_drops do
          assert quantity >= 1
          assert quantity <= 5
        end
      end
    end
  end

  describe "roll_table/1" do
    test "rolls directly from table struct" do
      table = Loot.get(1)
      drops = Loot.roll_table(table)

      assert is_list(drops)
    end
  end

  describe "gold_from_drops/1" do
    test "extracts gold amount from drops" do
      drops = [{0, 5}, {101, 1}, {0, 3}]

      assert Loot.gold_from_drops(drops) == 8
    end

    test "returns 0 when no gold" do
      drops = [{101, 1}, {102, 2}]

      assert Loot.gold_from_drops(drops) == 0
    end

    test "returns 0 for empty drops" do
      assert Loot.gold_from_drops([]) == 0
    end
  end

  describe "items_from_drops/1" do
    test "filters out gold" do
      drops = [{0, 5}, {101, 1}, {102, 2}]
      items = Loot.items_from_drops(drops)

      assert items == [{101, 1}, {102, 2}]
    end

    test "returns empty list when only gold" do
      drops = [{0, 5}, {0, 3}]

      assert Loot.items_from_drops(drops) == []
    end
  end

  describe "has_items?/1" do
    test "returns true when items present" do
      drops = [{0, 5}, {101, 1}]

      assert Loot.has_items?(drops)
    end

    test "returns false when only gold" do
      drops = [{0, 5}]

      refute Loot.has_items?(drops)
    end

    test "returns false for empty drops" do
      refute Loot.has_items?([])
    end
  end

  describe "has_gold?/1" do
    test "returns true when gold present" do
      drops = [{0, 5}, {101, 1}]

      assert Loot.has_gold?(drops)
    end

    test "returns false when no gold" do
      drops = [{101, 1}]

      refute Loot.has_gold?(drops)
    end

    test "returns false for empty drops" do
      refute Loot.has_gold?([])
    end
  end

  describe "loot table properties" do
    test "forest wolf table has expected entries" do
      table = Loot.get(1)

      # Should have gold entry
      gold = Enum.find(table.entries, fn e -> e.item_id == 0 end)
      assert gold != nil
      assert gold.chance == 100

      # Should have wolf pelt
      pelt = Enum.find(table.entries, fn e -> e.item_id == 101 end)
      assert pelt != nil
      assert pelt.chance == 50
    end

    test "cave spider table has rare drop" do
      table = Loot.get(2)

      # Should have rare spider eye
      eye = Enum.find(table.entries, fn e -> e.item_id == 203 end)
      assert eye != nil
      assert eye.chance == 5
    end
  end
end
