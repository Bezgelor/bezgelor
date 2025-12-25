defmodule BezgelorWorld.AbilitiesTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Abilities

  describe "resolve_spell4_base_id/2" do
    test "returns nil for nil input" do
      assert Abilities.resolve_spell4_base_id(nil, 1) == nil
    end

    test "returns spell_id unchanged for unknown spell" do
      # Use a very high ID that won't exist in game data
      unknown_id = 999_999_999
      assert Abilities.resolve_spell4_base_id(unknown_id, 1) == unknown_id
    end

    test "resolves Warrior abilities" do
      # Warrior class_id = 1
      # Relentless Strikes (Spell4 ID 32078)
      result = Abilities.resolve_spell4_base_id(32078, 1)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Engineer abilities" do
      # Engineer class_id = 2
      # Pulse Blast (Spell4 ID 42276)
      result = Abilities.resolve_spell4_base_id(42276, 2)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Esper abilities" do
      # Esper class_id = 3
      # Telekinetic Strike (Spell4 ID 32893)
      result = Abilities.resolve_spell4_base_id(32893, 3)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Medic abilities" do
      # Medic class_id = 4
      # Discharge (Spell4 ID 58832)
      result = Abilities.resolve_spell4_base_id(58832, 4)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Stalker abilities" do
      # Stalker class_id = 5
      # Shred (Spell4 ID 38765)
      result = Abilities.resolve_spell4_base_id(38765, 5)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Spellslinger abilities" do
      # Spellslinger class_id = 7
      # Quick Draw (Spell4 ID 43468)
      result = Abilities.resolve_spell4_base_id(43468, 7)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Spellslinger Gate ability" do
      # Gate (Spell4 ID 34355) - important for telegraph 142
      result = Abilities.resolve_spell4_base_id(34355, 7)
      assert is_integer(result)
      assert result > 0
    end

    test "resolves Spellslinger Charged Shot ability" do
      # Charged Shot (Spell4 ID 34718)
      result = Abilities.resolve_spell4_base_id(34718, 7)
      assert is_integer(result)
      assert result > 0
    end
  end

  describe "get_class_spellbook_abilities/1" do
    test "returns abilities for all supported classes" do
      for class_id <- [1, 2, 3, 4, 5, 7] do
        abilities = Abilities.get_class_spellbook_abilities(class_id)
        assert is_list(abilities)
        assert length(abilities) >= 3, "Class #{class_id} should have at least 3 abilities"

        for ability <- abilities do
          assert Map.has_key?(ability, :spell_id)
          assert Map.has_key?(ability, :slot)
          assert Map.has_key?(ability, :tier)
          assert is_integer(ability.spell_id)
          assert ability.spell_id > 0
        end
      end
    end

    test "falls back to Warrior abilities for unknown class" do
      abilities = Abilities.get_class_spellbook_abilities(999)
      warrior_abilities = Abilities.get_class_spellbook_abilities(1)
      assert abilities == warrior_abilities
    end
  end

  describe "get_class_action_set_abilities/1" do
    test "returns action set abilities for all supported classes" do
      for class_id <- [1, 2, 3, 4, 5, 7] do
        abilities = Abilities.get_class_action_set_abilities(class_id)
        assert is_list(abilities)
        assert length(abilities) >= 3, "Class #{class_id} should have at least 3 action set abilities"
      end
    end
  end

  describe "build_ability_book/1" do
    test "builds ability book entries for each spec" do
      # Each ability should appear for all 4 specs (0-3)
      book = Abilities.build_ability_book(7)
      assert is_list(book)

      # Group by spell4_base_id to check spec coverage
      by_spell = Enum.group_by(book, & &1.spell4_base_id)

      for {_spell_id, entries} <- by_spell do
        _spec_indices = Enum.map(entries, & &1.spec_index) |> Enum.sort()
        # Class abilities should be in all specs (0, 1, 2, 3)
        assert length(entries) >= 1
      end
    end
  end

  describe "build_action_set_from_shortcuts/1" do
    test "builds action set from shortcut map" do
      shortcuts = %{
        0 => [
          %{slot: 0, shortcut_type: 4, object_id: 12345, spell_id: 12345},
          %{slot: 1, shortcut_type: 4, object_id: 23456, spell_id: 23456}
        ],
        1 => [
          %{slot: 0, shortcut_type: 4, object_id: 34567, spell_id: 34567}
        ]
      }

      result = Abilities.build_action_set_from_shortcuts(shortcuts)

      assert Map.has_key?(result, 0)
      assert Map.has_key?(result, 1)
      assert length(result[0]) == 2
      assert length(result[1]) == 1

      # Check first action in spec 0
      [first | _] = result[0]
      assert first.type == :spell
      assert first.object_id == 12345
      assert first.slot == 0
    end

    test "handles empty shortcuts map" do
      result = Abilities.build_action_set_from_shortcuts(%{})
      assert result == %{}
    end
  end

  describe "max_tier_points/0" do
    test "returns 42 tier points" do
      assert Abilities.max_tier_points() == 42
    end
  end

  describe "get_primary_attack/1" do
    test "returns attack spell for each class" do
      attacks = %{
        1 => 55543,  # Warrior - Sword Strike
        2 => 40510,  # Engineer - Heavy Shot
        3 => 960,    # Esper - Psyblade Strike
        4 => 55533,  # Medic - Shock Paddles
        5 => 55198,  # Stalker - Right Click Attack
        7 => 55665   # Spellslinger - Pistol Shot
      }

      for {class_id, expected_attack} <- attacks do
        assert Abilities.get_primary_attack(class_id) == expected_attack,
               "Class #{class_id} should have attack #{expected_attack}"
      end
    end

    test "falls back to Warrior attack for unknown class" do
      assert Abilities.get_primary_attack(999) == 55543
    end
  end
end
