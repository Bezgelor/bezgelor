defmodule BezgelorCore.CharacterStatsTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.CharacterStats

  describe "compute_combat_stats/1" do
    test "computes combat stats from base character data" do
      character = %{
        level: 10,
        # Warrior
        class: 1,
        # Human
        race: 0
      }

      stats = CharacterStats.compute_combat_stats(character)

      assert stats.power > 0
      assert stats.tech > 0
      assert stats.support > 0
      assert stats.crit_chance >= 5
      assert stats.armor > 0
    end

    test "higher level characters have higher stats" do
      low_level = CharacterStats.compute_combat_stats(%{level: 1, class: 1, race: 0})
      high_level = CharacterStats.compute_combat_stats(%{level: 50, class: 1, race: 0})

      assert high_level.power > low_level.power
      assert high_level.armor > low_level.armor
    end

    test "assault classes favor power" do
      # Warrior
      warrior = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})
      # Esper/healer
      esper = CharacterStats.compute_combat_stats(%{level: 10, class: 4, race: 0})

      assert warrior.power >= esper.power
    end
  end

  describe "get_stat_modifier/2" do
    test "buff manager stat modifiers add to computed stats" do
      base_stats = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})

      # Simulate +50 power buff
      modified = CharacterStats.apply_buff_modifiers(base_stats, %{power: 50, armor: 0})

      assert modified.power == base_stats.power + 50
    end
  end
end
