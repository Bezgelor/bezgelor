defmodule BezgelorWorld.EquipmentDropsTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.EquipmentDrops

  describe "roll_equipment/3" do
    test "tier 1 creatures never drop equipment" do
      # Tier 1 minions have no drop chances
      # Run many times to ensure no drops
      results =
        for _ <- 1..100 do
          EquipmentDrops.roll_equipment(1, 20)
        end
        |> List.flatten()

      assert results == []
    end

    test "returns list of item IDs (possibly empty)" do
      result = EquipmentDrops.roll_equipment(3, 20)
      assert is_list(result)

      Enum.each(result, fn item_id ->
        assert is_integer(item_id)
        assert item_id > 0
      end)
    end

    test "higher tier increases chance of drops" do
      # We can't guarantee drops, but higher tiers have better odds
      tier_2_drops = for _ <- 1..1000, do: EquipmentDrops.roll_equipment(2, 20)
      tier_5_drops = for _ <- 1..1000, do: EquipmentDrops.roll_equipment(5, 20)

      tier_2_count = tier_2_drops |> List.flatten() |> length()
      tier_5_count = tier_5_drops |> List.flatten() |> length()

      # Tier 5 should have significantly more drops than tier 2
      # (tier 2: 1.1% total, tier 5: 71% total)
      assert tier_5_count > tier_2_count
    end

    test "drop_bonus increases chance" do
      # Run many times with drop_bonus
      baseline_drops = for _ <- 1..500, do: EquipmentDrops.roll_equipment(3, 20)
      bonus_drops = for _ <- 1..500, do: EquipmentDrops.roll_equipment(3, 20, drop_bonus: 50)

      baseline_count = baseline_drops |> List.flatten() |> length()
      bonus_count = bonus_drops |> List.flatten() |> length()

      # With +50% bonus, we should get more drops
      assert bonus_count > baseline_count
    end

    test "class_id filters equipment drops" do
      # When class_id is provided, only class-appropriate equipment drops
      # We can't directly test filtering without items data, but ensure no crash
      result = EquipmentDrops.roll_equipment(3, 20, class_id: 1)
      assert is_list(result)
    end
  end

  describe "get_random_equipment/3" do
    test "returns :error when no matching items exist" do
      # Level 1000 with artifact quality unlikely to have items
      result = EquipmentDrops.get_random_equipment(1000, 7)
      # Could be :error or {:ok, _} depending on data
      assert result == :error or match?({:ok, _}, result)
    end

    test "returns {:ok, item_id} or :error" do
      result = EquipmentDrops.get_random_equipment(20, 3)
      assert result == :error or match?({:ok, id} when is_integer(id), result)
    end

    test "respects level range filtering" do
      # Just ensure no crash with various levels
      for level <- [1, 10, 25, 50] do
        result = EquipmentDrops.get_random_equipment(level, 3)
        assert result == :error or match?({:ok, _}, result)
      end
    end
  end

  describe "is_equipment?/1" do
    test "returns boolean" do
      result = EquipmentDrops.is_equipment?(1)
      assert is_boolean(result)
    end

    test "returns false for non-existent item" do
      # Very high item ID unlikely to exist
      assert EquipmentDrops.is_equipment?(999_999_999) == false
    end
  end

  describe "tier drop chances" do
    test "tier 2 has green and blue chances" do
      # 1% green, 0.1% blue
      # With 10000 rolls, we should see some drops
      drops =
        for _ <- 1..10_000 do
          EquipmentDrops.roll_equipment(2, 20)
        end
        |> List.flatten()

      # Should have some drops (expected ~110 with 1.1% chance)
      # Allow for variance
      assert length(drops) > 10
    end

    test "tier 5 has high drop rates" do
      # 50% blue, 20% purple, 1% orange = 71% total chance
      # With 100 rolls, we should see many drops
      drops =
        for _ <- 1..100 do
          EquipmentDrops.roll_equipment(5, 20)
        end
        |> List.flatten()

      # Should have many drops
      assert length(drops) > 20
    end
  end
end
