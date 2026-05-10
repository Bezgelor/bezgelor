defmodule BezgelorData.SpellDataTest do
  use ExUnit.Case, async: true

  alias BezgelorData.SpellData

  # Quick Draw - a well-known spell with effects
  @test_spell_id 43468

  describe "get/1" do
    test "returns SpellData struct for valid spell" do
      assert {:ok, %SpellData{} = data} = SpellData.get(@test_spell_id)
      assert data.id == @test_spell_id
      assert is_map(data.entry)
      assert is_list(data.effects)
      assert is_list(data.telegraphs)
    end

    test "returns :error for invalid spell" do
      assert :error = SpellData.get(999_999_999)
    end
  end

  describe "get!/1" do
    test "returns SpellData struct for valid spell" do
      assert %SpellData{id: @test_spell_id} = SpellData.get!(@test_spell_id)
    end

    test "raises for invalid spell" do
      assert_raise RuntimeError, ~r/not found/, fn ->
        SpellData.get!(999_999_999)
      end
    end
  end

  describe "effects/1" do
    test "returns list of effect maps" do
      effects = SpellData.effects(@test_spell_id)
      assert is_list(effects)
      assert length(effects) > 0

      # Each effect should be a map with effectType
      effect = hd(effects)
      assert is_map(effect)
      assert Map.has_key?(effect, :effectType) or Map.has_key?(effect, "effectType")
    end

    test "returns empty list for spell without effects" do
      # Find a spell without effects or use a known one
      # For now, test that non-existent returns empty
      assert [] = SpellData.effects(999_999_999)
    end
  end

  describe "effect_ids/1" do
    test "returns list of integer IDs" do
      ids = SpellData.effect_ids(@test_spell_id)
      assert is_list(ids)
      assert length(ids) > 0
      assert Enum.all?(ids, &is_integer/1)
    end

    test "returns empty list for invalid spell" do
      assert [] = SpellData.effect_ids(999_999_999)
    end
  end

  describe "telegraphs/1" do
    test "returns list for any spell" do
      telegraphs = SpellData.telegraphs(@test_spell_id)
      assert is_list(telegraphs)
    end
  end

  describe "telegraph_ids/1" do
    test "returns list for any spell" do
      ids = SpellData.telegraph_ids(@test_spell_id)
      assert is_list(ids)
    end
  end

  describe "exists?/1" do
    test "returns true for valid spell" do
      assert SpellData.exists?(@test_spell_id)
    end

    test "returns false for invalid spell" do
      refute SpellData.exists?(999_999_999)
    end
  end

  describe "has_effects?/1" do
    test "returns true for spell with effects" do
      assert SpellData.has_effects?(@test_spell_id)
    end

    test "returns false for invalid spell" do
      refute SpellData.has_effects?(999_999_999)
    end
  end

  describe "has_telegraphs?/1" do
    test "returns boolean" do
      result = SpellData.has_telegraphs?(@test_spell_id)
      assert is_boolean(result)
    end
  end

  describe "get_entry/1" do
    test "returns {:ok, map} for valid spell" do
      assert {:ok, entry} = SpellData.get_entry(@test_spell_id)
      assert is_map(entry)
    end

    test "returns :error for invalid spell" do
      assert :error = SpellData.get_entry(999_999_999)
    end
  end

  describe "get_effect/1" do
    test "returns effect map for valid effect ID" do
      [effect_id | _] = SpellData.effect_ids(@test_spell_id)
      effect = SpellData.get_effect(effect_id)
      assert is_map(effect)
    end

    test "returns nil for invalid effect ID" do
      assert nil == SpellData.get_effect(999_999_999)
    end
  end
end
