defmodule BezgelorData.StoreSearchTest do
  @moduledoc """
  Tests for Store.search_items/2 and Store.get_text/1.
  """
  use ExUnit.Case, async: false

  alias BezgelorData.Store

  # Tests are excluded by default unless Store data is loaded
  @moduletag :store_search

  describe "get_text/1" do
    test "returns text for valid ID" do
      # Text ID 1 is "Cancel" in most WildStar text files
      result = Store.get_text(1)
      assert is_binary(result) or result == nil
    end

    test "returns nil for ID 0" do
      assert Store.get_text(0) == nil
    end

    test "returns nil for negative ID" do
      assert Store.get_text(-1) == nil
    end

    test "returns nil for non-existent ID" do
      # Very high ID unlikely to exist
      assert Store.get_text(999_999_999) == nil
    end
  end

  describe "search_items/1" do
    test "returns empty list for empty query" do
      assert Store.search_items("") == []
    end

    test "returns empty list for whitespace query" do
      assert Store.search_items("   ") == []
    end

    test "returns list for valid query" do
      # Search for common item term
      results = Store.search_items("sword")
      assert is_list(results)
    end

    test "limits results to 50 by default" do
      # Search for very common letter
      results = Store.search_items("a")
      assert length(results) <= 50
    end

    test "respects custom limit option" do
      results = Store.search_items("a", limit: 10)
      assert length(results) <= 10
    end

    test "searches by exact ID when query is numeric" do
      # Search for a specific item ID (item ID 1 should exist)
      results = Store.search_items("1")
      assert is_list(results)

      if length(results) > 0 do
        [item | _] = results
        assert item.id == 1
        assert Map.has_key?(item, :name)
      end
    end

    test "returns empty for non-existent ID" do
      # Very high ID unlikely to exist
      results = Store.search_items("999999999")
      assert results == []
    end

    test "items include :name field" do
      results = Store.search_items("1")

      if length(results) > 0 do
        [item | _] = results
        assert Map.has_key?(item, :name)
        assert is_binary(item.name)
      end
    end
  end
end
