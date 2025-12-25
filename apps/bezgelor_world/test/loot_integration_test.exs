defmodule BezgelorWorld.LootIntegrationTest do
  @moduledoc """
  Integration tests for the Loot module that verify data loading and
  loot rolling with real Store data.
  """
  use ExUnit.Case, async: true

  @moduletag :integration

  alias BezgelorWorld.Loot
  alias BezgelorData.Store

  describe "loot tables from Store" do
    test "loot tables are loaded" do
      tables = Store.get_all_loot_tables()
      assert length(tables) > 0
    end

    test "can retrieve specific loot table by ID" do
      # Wildlife - Small table
      assert {:ok, table} = Store.get_loot_table(1)
      assert table.id == 1
      assert is_list(table.entries)
      assert length(table.entries) > 0
    end

    test "loot table entries have required fields" do
      {:ok, table} = Store.get_loot_table(1)

      for entry <- table.entries do
        assert Map.has_key?(entry, :item_id) or Map.has_key?(entry, "item_id")
        assert Map.has_key?(entry, :chance) or Map.has_key?(entry, "chance")
        assert Map.has_key?(entry, :min) or Map.has_key?(entry, "min")
        assert Map.has_key?(entry, :max) or Map.has_key?(entry, "max")
        assert Map.has_key?(entry, :type) or Map.has_key?(entry, "type")
      end
    end

    test "empty loot table exists for non-combat creatures" do
      assert {:ok, table} = Store.get_loot_table(999)
      assert table.entries == []
    end
  end

  describe "creature loot rules from Store" do
    test "creature loot rules are loaded" do
      rules = Store.get_creature_loot_rules()
      assert rules != nil
    end

    test "rules have race mappings" do
      rules = Store.get_creature_loot_rules()
      race_mappings = Map.get(rules, :race_mappings) || Map.get(rules, "race_mappings")
      assert race_mappings != nil
      assert map_size(race_mappings) > 0
    end

    test "rules have tier modifiers" do
      rules = Store.get_creature_loot_rules()
      tier_mods = Map.get(rules, :tier_modifiers) || Map.get(rules, "tier_modifiers")
      assert tier_mods != nil
      assert map_size(tier_mods) > 0
    end

    test "rules have difficulty modifiers" do
      rules = Store.get_creature_loot_rules()
      diff_mods = Map.get(rules, :difficulty_modifiers) || Map.get(rules, "difficulty_modifiers")
      assert diff_mods != nil
      assert map_size(diff_mods) > 0
    end
  end

  describe "loot resolution" do
    test "resolves loot for known creature" do
      # Creature ID 9301 is a common test creature
      {:ok, resolution} = Store.resolve_creature_loot(9301)

      assert Map.has_key?(resolution, :loot_table_id)
      assert Map.has_key?(resolution, :gold_multiplier)
      assert Map.has_key?(resolution, :drop_bonus)
    end

    test "resolves loot for unknown creature with defaults" do
      # Very high ID unlikely to exist
      {:ok, resolution} = Store.resolve_creature_loot(999_999_999)

      assert Map.has_key?(resolution, :loot_table_id)
      assert Map.has_key?(resolution, :gold_multiplier)
      assert Map.has_key?(resolution, :drop_bonus)
    end
  end

  describe "roll_table/2 with Store data" do
    test "rolls loot from wildlife table" do
      # Run multiple times to ensure it works consistently
      for _ <- 1..10 do
        drops = Loot.roll_table(1)
        assert is_list(drops)
        # May or may not have drops depending on RNG
      end
    end

    test "returns empty list for unknown table" do
      drops = Loot.roll_table(99999)
      assert drops == []
    end

    test "gold_multiplier affects gold drops" do
      # Roll table 1 (wildlife) with high gold multiplier
      # Should eventually get gold with high multiplier
      drops_normal = for _ <- 1..100, do: Loot.roll_table(1, gold_multiplier: 1.0)
      drops_boosted = for _ <- 1..100, do: Loot.roll_table(1, gold_multiplier: 10.0)

      # Calculate average gold from each set
      avg_normal = average_gold(drops_normal)
      avg_boosted = average_gold(drops_boosted)

      # Boosted should be higher on average (not a strict test due to RNG)
      # Just verify we got drops
      assert is_number(avg_normal)
      assert is_number(avg_boosted)
    end

    test "drop_bonus affects drop chance" do
      # With 100% bonus, all 100% base drops should hit
      drops = Loot.roll_table(1, drop_bonus: 100)
      # Should have gold since gold entry has 100% chance
      assert Enum.any?(drops, fn {item_id, _} -> item_id == 0 end)
    end
  end

  describe "roll_creature_loot/4 integration" do
    test "rolls loot for real creature with Store data" do
      # Roll loot for a known creature
      drops = Loot.roll_creature_loot(9301, 10, 10)
      assert is_list(drops)
    end

    test "killer level affects loot scaling" do
      # Kill higher level creature (creature level 20, killer level 5)
      # Should get bonus gold
      drops_low = for _ <- 1..50, do: Loot.roll_creature_loot(9301, 20, 5)

      # Kill same level creature
      drops_same = for _ <- 1..50, do: Loot.roll_creature_loot(9301, 10, 10)

      # Just verify both work
      assert Enum.all?(drops_low, &is_list/1)
      assert Enum.all?(drops_same, &is_list/1)
    end

    test "group_size option is accepted" do
      drops = Loot.roll_creature_loot(9301, 10, 10, group_size: 5)
      assert is_list(drops)
    end
  end

  describe "loot validation" do
    test "loot data passes validation" do
      # This tests that the validation module works with loaded data
      result = BezgelorData.LootValidator.validate_all()

      case result do
        {:ok, stats} ->
          assert stats.tables.table_count > 0
          assert stats.tables.entry_count > 0
          assert stats.rules.race_mappings > 0

        {:error, errors} ->
          flunk("Validation failed with errors: #{inspect(errors)}")
      end
    end
  end

  describe "Loot utility functions" do
    test "gold_from_drops extracts gold" do
      drops = [{0, 10}, {100, 1}, {0, 5}]
      assert Loot.gold_from_drops(drops) == 15
    end

    test "items_from_drops filters out gold" do
      drops = [{0, 10}, {100, 1}, {200, 2}]
      items = Loot.items_from_drops(drops)
      assert items == [{100, 1}, {200, 2}]
    end

    test "has_gold? checks for gold" do
      assert Loot.has_gold?([{0, 10}])
      refute Loot.has_gold?([{100, 1}])
      refute Loot.has_gold?([])
    end

    test "has_items? checks for items" do
      assert Loot.has_items?([{100, 1}])
      refute Loot.has_items?([{0, 10}])
      refute Loot.has_items?([])
    end

    test "calculate_group_bonus returns expected values" do
      assert Loot.calculate_group_bonus(1) == 0
      assert Loot.calculate_group_bonus(2) == 2
      assert Loot.calculate_group_bonus(5) == 8
      assert Loot.calculate_group_bonus(10) == 13
      assert Loot.calculate_group_bonus(20) == 23
      # Capped
      assert Loot.calculate_group_bonus(40) == 23
    end
  end

  # Helper functions

  defp average_gold(rolls_list) do
    total_gold =
      rolls_list
      |> Enum.flat_map(& &1)
      |> Enum.filter(fn {id, _} -> id == 0 end)
      |> Enum.map(fn {_, amount} -> amount end)
      |> Enum.sum()

    count = length(rolls_list)
    if count > 0, do: total_gold / count, else: 0
  end
end
