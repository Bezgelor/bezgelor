defmodule BezgelorWorld.LootTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Loot.LootRules

  describe "LootRules.default_method/2" do
    test "raids use personal loot" do
      assert LootRules.default_method(:raid, :normal) == :personal
      assert LootRules.default_method(:raid, :veteran) == :personal
    end

    test "mythic+ uses personal loot" do
      assert LootRules.default_method(:dungeon, :mythic_plus) == :personal
    end

    test "expeditions use personal loot" do
      assert LootRules.default_method(:expedition, :normal) == :personal
    end

    test "normal dungeons use need before greed" do
      assert LootRules.default_method(:dungeon, :normal) == :need_before_greed
      assert LootRules.default_method(:dungeon, :veteran) == :need_before_greed
    end
  end

  describe "LootRules.requires_roll?/2" do
    test "personal loot never requires roll" do
      refute LootRules.requires_roll?(%{quality: 5}, :personal)
    end

    test "master loot never requires roll" do
      refute LootRules.requires_roll?(%{quality: 5}, :master_loot)
    end

    test "group loot requires roll for rare+" do
      # Uncommon
      refute LootRules.requires_roll?(%{quality: 2}, :group_loot)
      # Rare
      assert LootRules.requires_roll?(%{quality: 3}, :group_loot)
      # Epic
      assert LootRules.requires_roll?(%{quality: 4}, :group_loot)
    end

    test "need before greed requires roll for uncommon+" do
      # Common
      refute LootRules.requires_roll?(%{quality: 1}, :need_before_greed)
      # Uncommon
      assert LootRules.requires_roll?(%{quality: 2}, :need_before_greed)
      # Rare
      assert LootRules.requires_roll?(%{quality: 3}, :need_before_greed)
    end
  end

  describe "LootRules.determine_winner/1" do
    test "returns nil for empty rolls" do
      assert LootRules.determine_winner([]) == nil
    end

    test "returns nil when all pass" do
      rolls = [
        %{character_id: 1, roll_type: :pass, roll_value: 0},
        %{character_id: 2, roll_type: :pass, roll_value: 0}
      ]

      assert LootRules.determine_winner(rolls) == nil
    end

    test "need beats greed regardless of roll value" do
      rolls = [
        %{character_id: 1, roll_type: :need, roll_value: 10},
        %{character_id: 2, roll_type: :greed, roll_value: 100}
      ]

      winner = LootRules.determine_winner(rolls)
      assert winner.character_id == 1
      assert winner.roll_type == :need
    end

    test "higher roll wins among same roll type" do
      rolls = [
        %{character_id: 1, roll_type: :greed, roll_value: 50},
        %{character_id: 2, roll_type: :greed, roll_value: 75},
        %{character_id: 3, roll_type: :greed, roll_value: 25}
      ]

      winner = LootRules.determine_winner(rolls)
      assert winner.character_id == 2
      assert winner.roll_value == 75
    end

    test "single need wins" do
      rolls = [
        %{character_id: 1, roll_type: :need, roll_value: 42},
        %{character_id: 2, roll_type: :pass, roll_value: 0},
        %{character_id: 3, roll_type: :pass, roll_value: 0}
      ]

      winner = LootRules.determine_winner(rolls)
      assert winner.character_id == 1
    end
  end

  describe "LootRules.roll/0" do
    test "generates values between 1 and 100" do
      # Run many times to verify range
      rolls = for _ <- 1..100, do: LootRules.roll()

      assert Enum.all?(rolls, &(&1 >= 1 and &1 <= 100))
    end
  end

  describe "LootRules.can_need?/2" do
    test "allows need when no restrictions" do
      character = %{class_id: 1}
      item = %{}

      assert LootRules.can_need?(character, item)
    end

    test "respects class restriction" do
      character = %{class_id: 1}
      item = %{class_restriction: [2, 3]}

      refute LootRules.can_need?(character, item)
    end

    test "allows when class is in restriction list" do
      character = %{class_id: 2}
      item = %{class_restriction: [2, 3]}

      assert LootRules.can_need?(character, item)
    end

    test "respects armor type" do
      # Warrior (1) can wear heavy
      warrior = %{class_id: 1}
      heavy_armor = %{armor_type: :heavy}
      light_armor = %{armor_type: :light}

      assert LootRules.can_need?(warrior, heavy_armor)
      refute LootRules.can_need?(warrior, light_armor)

      # Esper (2) can wear light
      esper = %{class_id: 2}
      assert LootRules.can_need?(esper, light_armor)
      refute LootRules.can_need?(esper, heavy_armor)
    end
  end

  describe "LootRules.apply_luck_bonus/2" do
    test "increases chance based on luck" do
      assert LootRules.apply_luck_bonus(10, 0) == 10
      assert LootRules.apply_luck_bonus(10, 100) == 20
      assert LootRules.apply_luck_bonus(10, 500) == 60
    end

    test "caps at 100%" do
      assert LootRules.apply_luck_bonus(90, 500) == 100
    end
  end

  describe "LootRules.calculate_personal_loot/3" do
    test "filters by eligibility" do
      # Warrior - heavy armor
      character = %{class_id: 1}

      loot_table = [
        %{id: 1, armor_type: :heavy, drop_chance: 100},
        %{id: 2, armor_type: :light, drop_chance: 100},
        # Anyone can get
        %{id: 3, bind_on_pickup: false, drop_chance: 100}
      ]

      # Seed random for deterministic test
      :rand.seed(:exsss, {1, 2, 3})

      loot = LootRules.calculate_personal_loot(character, loot_table)

      # Should include heavy armor and BoE items, not light armor
      item_ids = Enum.map(loot, & &1.id)
      # At least one should drop
      assert 1 in item_ids or 3 in item_ids
      # Light armor shouldn't drop for warrior
      refute 2 in item_ids
    end
  end
end
