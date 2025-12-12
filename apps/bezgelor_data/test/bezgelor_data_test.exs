defmodule BezgelorDataTest do
  use ExUnit.Case

  describe "creatures" do
    test "get_creature returns creature by ID" do
      {:ok, creature} = BezgelorData.get_creature(1)
      assert creature.id == 1
      assert is_integer(creature.name_text_id)
      assert is_integer(creature.tier_id)
    end

    test "get_creature returns :error for missing creature" do
      assert BezgelorData.get_creature(999_999_999) == :error
    end

    test "get_creature! returns creature" do
      creature = BezgelorData.get_creature!(1)
      assert creature.id == 1
    end

    test "get_creature! raises for missing creature" do
      assert_raise RuntimeError, "Creature 999999999 not found", fn ->
        BezgelorData.get_creature!(999_999_999)
      end
    end

    test "list_creatures returns all creatures" do
      creatures = BezgelorData.list_creatures()
      assert is_list(creatures)
      assert length(creatures) > 0
    end

    test "creatures_by_tier filters by tier" do
      creatures = BezgelorData.creatures_by_tier(1)
      assert is_list(creatures)
      assert Enum.all?(creatures, fn c -> c.tier_id == 1 end)
    end

    test "creatures_by_difficulty filters by difficulty" do
      creatures = BezgelorData.creatures_by_difficulty(2)
      assert is_list(creatures)
      assert Enum.all?(creatures, fn c -> c.difficulty_id == 2 end)
    end

    test "creatures_by_archetype filters by archetype" do
      creatures = BezgelorData.creatures_by_archetype(1)
      assert is_list(creatures)
      assert Enum.all?(creatures, fn c -> c.archetype_id == 1 end)
    end
  end

  describe "zones" do
    test "get_zone returns zone by ID" do
      # Zone 12 is the first zone in WorldZone.tbl
      {:ok, zone} = BezgelorData.get_zone(12)
      assert zone.id == 12
      assert is_integer(zone.name_text_id)
    end

    test "get_zone returns :error for missing zone" do
      assert BezgelorData.get_zone(999_999_999) == :error
    end

    test "list_zones returns all zones" do
      zones = BezgelorData.list_zones()
      assert is_list(zones)
      assert length(zones) > 0
    end

    test "zones_by_pvp_rules filters by PvP rules" do
      # PvP rules 0 = no PvP
      zones = BezgelorData.zones_by_pvp_rules(0)
      assert is_list(zones)
      assert Enum.all?(zones, fn z -> z.pvp_rules == 0 end)
    end

    test "child_zones returns zones with specific parent" do
      # Zone 16 has child zone 17
      children = BezgelorData.child_zones(16)
      assert is_list(children)
      assert Enum.all?(children, fn z -> z.parent_zone_id == 16 end)
    end

    test "root_zones returns zones with no parent" do
      roots = BezgelorData.root_zones()
      assert is_list(roots)
      assert Enum.all?(roots, fn z -> z.parent_zone_id == nil end)
    end

    test "accessible_zones returns zones with allow_access = true" do
      zones = BezgelorData.accessible_zones()
      assert is_list(zones)
      assert Enum.all?(zones, fn z -> z.allow_access == true end)
    end
  end

  describe "spells" do
    test "get_spell returns spell by ID" do
      {:ok, spell} = BezgelorData.get_spell(1)
      assert spell.id == 1
      assert is_integer(spell.tier_index)
    end

    test "get_spell returns :error for missing spell" do
      assert BezgelorData.get_spell(999_999_999) == :error
    end

    test "list_spells returns all spells" do
      spells = BezgelorData.list_spells()
      assert is_list(spells)
      assert length(spells) > 0
    end

    test "spells_by_base filters by base spell ID" do
      spells = BezgelorData.spells_by_base(0)
      assert is_list(spells)
      assert Enum.all?(spells, fn s -> s.base_spell_id == 0 end)
    end
  end

  describe "items" do
    test "get_item returns item by ID" do
      {:ok, item} = BezgelorData.get_item(1)
      assert item.id == 1
      assert is_integer(item.name_text_id)
      assert is_integer(item.quality_id)
    end

    test "get_item returns :error for missing item" do
      assert BezgelorData.get_item(999_999_999) == :error
    end

    test "list_items returns all items" do
      items = BezgelorData.list_items()
      assert is_list(items)
      assert length(items) > 0
    end

    test "items_by_type filters by type ID" do
      items = BezgelorData.items_by_type(1)
      assert is_list(items)
      assert Enum.all?(items, fn i -> i.type_id == 1 end)
    end

    test "items_by_quality filters by quality ID" do
      # Quality 3 = epic
      items = BezgelorData.items_by_quality(3)
      assert is_list(items)
      assert Enum.all?(items, fn i -> i.quality_id == 3 end)
    end

    test "items_by_family filters by family ID" do
      items = BezgelorData.items_by_family(1)
      assert is_list(items)
      assert Enum.all?(items, fn i -> i.family_id == 1 end)
    end

    test "items_by_category filters by category ID" do
      items = BezgelorData.items_by_category(1)
      assert is_list(items)
      assert Enum.all?(items, fn i -> i.category_id == 1 end)
    end
  end

  describe "texts" do
    test "get_text returns text by ID" do
      # Text ID 51 contains the language name
      {:ok, text} = BezgelorData.get_text(51)
      assert is_binary(text)
      assert String.contains?(text, "English")
    end

    test "get_text returns :error for missing text" do
      # Use a very high ID unlikely to exist
      assert BezgelorData.get_text(999_999_999) == :error
    end

    test "get_text! returns text" do
      text = BezgelorData.get_text!(51)
      assert String.contains?(text, "English")
    end

    test "get_text! raises for missing text" do
      assert_raise RuntimeError, "Text 999999999 not found", fn ->
        BezgelorData.get_text!(999_999_999)
      end
    end

    test "text_or_nil returns text or nil" do
      assert BezgelorData.text_or_nil(51) |> String.contains?("English")
      assert BezgelorData.text_or_nil(999_999_999) == nil
    end
  end

  describe "entities with names" do
    test "get_creature_with_name includes resolved name" do
      {:ok, creature} = BezgelorData.get_creature_with_name(1)
      assert creature.id == 1
      assert Map.has_key?(creature, :name)
      assert is_binary(creature.name)
    end

    test "get_zone_with_name includes resolved name" do
      {:ok, zone} = BezgelorData.get_zone_with_name(12)
      assert zone.id == 12
      assert Map.has_key?(zone, :name)
      assert is_binary(zone.name)
    end

    test "get_item_with_name includes resolved name and tooltip" do
      {:ok, item} = BezgelorData.get_item_with_name(1)
      assert item.id == 1
      assert Map.has_key?(item, :name)
      assert Map.has_key?(item, :tooltip)
      assert is_binary(item.name)
      assert is_binary(item.tooltip)
    end
  end

  describe "stats" do
    test "stats returns counts of all data types" do
      stats = BezgelorData.stats()

      assert is_integer(stats.creatures)
      assert is_integer(stats.zones)
      assert is_integer(stats.spells)
      assert is_integer(stats.items)
      assert is_integer(stats.texts)

      # Should have real data loaded
      assert stats.creatures > 1000
      assert stats.zones > 100
      assert stats.spells > 1000
      assert stats.items > 1000
      assert stats.texts > 100_000
    end
  end

  describe "Store pagination" do
    alias BezgelorData.Store

    test "list_paginated returns first page of items" do
      {items, continuation} = Store.list_paginated(:creatures, 10)

      assert is_list(items)
      assert length(items) == 10
      assert continuation != nil
    end

    test "list_continue returns next page" do
      {first_page, continuation} = Store.list_paginated(:creatures, 10)
      {second_page, _cont2} = Store.list_continue(continuation)

      assert is_list(second_page)
      assert length(second_page) == 10

      # Pages should have different items
      first_ids = Enum.map(first_page, & &1.id) |> MapSet.new()
      second_ids = Enum.map(second_page, & &1.id) |> MapSet.new()
      assert MapSet.disjoint?(first_ids, second_ids)
    end

    test "list_continue with nil returns empty list" do
      {items, continuation} = Store.list_continue(nil)

      assert items == []
      assert continuation == nil
    end

    test "pagination iterates through all items" do
      total_count = Store.count(:zones)

      # Collect all items through pagination
      all_items = collect_paginated(:zones, 20)

      # Should get same count as total
      assert length(all_items) == total_count
    end

    test "list_filtered returns matching items" do
      # Filter creatures by tier
      filter_fn = fn creature -> creature.tier_id == 1 end
      {items, _continuation} = Store.list_filtered(:creatures, filter_fn, 50)

      assert is_list(items)
      assert Enum.all?(items, fn c -> c.tier_id == 1 end)
    end

    test "list_filtered_continue continues filtered iteration" do
      filter_fn = fn creature -> creature.tier_id == 1 end
      {_first_page, continuation} = Store.list_filtered(:creatures, filter_fn, 10)
      {second_page, _cont2} = Store.list_filtered_continue(continuation)

      assert is_list(second_page)
      # All items should still match filter
      assert Enum.all?(second_page, fn c -> c.tier_id == 1 end)
    end

    test "collect_all_pages collects entire filtered result" do
      filter_fn = fn zone -> zone.pvp_rules == 0 end

      # Collect using pagination
      result = Store.list_filtered(:zones, filter_fn, 10)
      all_filtered = Store.collect_all_pages(result, &Store.list_filtered_continue/1)

      # Compare with non-paginated filter
      all_zones = Store.list(:zones)
      expected = Enum.filter(all_zones, filter_fn)

      assert length(all_filtered) == length(expected)
    end

    # Helper to collect all items through pagination
    defp collect_paginated(table, page_size) do
      {items, continuation} = Store.list_paginated(table, page_size)
      collect_paginated_loop(items, continuation)
    end

    defp collect_paginated_loop(acc, nil), do: acc

    defp collect_paginated_loop(acc, continuation) do
      {items, new_continuation} = Store.list_continue(continuation)
      collect_paginated_loop(acc ++ items, new_continuation)
    end
  end
end
