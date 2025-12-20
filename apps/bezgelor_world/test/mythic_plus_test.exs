defmodule BezgelorWorld.MythicPlusTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.MythicPlus.{Keystone, Affix}

  describe "Keystone.new/3" do
    test "creates keystone with correct properties" do
      keystone = Keystone.new(1, 100, 5)

      assert keystone.character_id == 1
      assert keystone.dungeon_id == 100
      assert keystone.level == 5
      assert keystone.depleted == false
      assert is_list(keystone.affix_ids)
    end

    test "higher levels have more affixes" do
      key_lvl2 = Keystone.new(1, 100, 2)
      key_lvl7 = Keystone.new(1, 100, 7)
      key_lvl10 = Keystone.new(1, 100, 10)

      assert length(key_lvl2.affix_ids) >= 1
      assert length(key_lvl7.affix_ids) >= 3
      assert length(key_lvl10.affix_ids) >= 4
    end
  end

  describe "Keystone.calculate_time_bonus/2" do
    test "under 60% gives +3 levels" do
      time_limit = 1_000_000
      # 50%
      completion = 500_000

      assert Keystone.calculate_time_bonus(time_limit, completion) == 3
    end

    test "under 80% gives +2 levels" do
      time_limit = 1_000_000
      # 70%
      completion = 700_000

      assert Keystone.calculate_time_bonus(time_limit, completion) == 2
    end

    test "under 100% gives +1 level" do
      time_limit = 1_000_000
      # 90%
      completion = 900_000

      assert Keystone.calculate_time_bonus(time_limit, completion) == 1
    end

    test "over time gives no bonus" do
      time_limit = 1_000_000
      # 110%
      completion = 1_100_000

      assert Keystone.calculate_time_bonus(time_limit, completion) == 0
    end
  end

  describe "Keystone.upgrade/2" do
    test "upgrades level by time bonus" do
      keystone = Keystone.new(1, 100, 5)
      upgraded = Keystone.upgrade(keystone, 2)

      assert upgraded.level == 7
      assert upgraded.depleted == false
      # Dungeon changes on upgrade
      assert upgraded.dungeon_id != nil
    end
  end

  describe "Keystone.deplete/1" do
    test "depletes keystone and reduces level" do
      keystone = Keystone.new(1, 100, 5)
      depleted = Keystone.deplete(keystone)

      assert depleted.level == 4
      assert depleted.depleted == true
    end

    test "cannot go below level 2" do
      keystone = Keystone.new(1, 100, 2)
      depleted = Keystone.deplete(keystone)

      assert depleted.level == 2
    end
  end

  describe "Affix.get_affix/1" do
    test "returns affix definition" do
      affix = Affix.get_affix(1)

      assert affix.name == "Fortified"
      assert affix.tier == 1
    end

    test "returns nil for unknown affix" do
      assert Affix.get_affix(999) == nil
    end
  end

  describe "Affix.get_stat_modifiers/2" do
    test "fortified boosts trash mobs" do
      mods = Affix.get_stat_modifiers([1], :trash)

      assert mods.health_mult == 1.3
      assert mods.damage_mult == 1.2
    end

    test "fortified doesn't boost bosses" do
      mods = Affix.get_stat_modifiers([1], :boss)

      assert mods.health_mult == 1.0
      assert mods.damage_mult == 1.0
    end

    test "tyrannical boosts bosses" do
      mods = Affix.get_stat_modifiers([2], :boss)

      assert mods.health_mult == 1.4
      assert mods.damage_mult == 1.15
    end

    test "multiple affixes stack" do
      # Fortified + some other affix
      mods = Affix.get_stat_modifiers([1, 3], :trash)

      # Should have fortified's multipliers
      assert mods.health_mult >= 1.3
    end
  end

  describe "Affix.process_trigger/3" do
    test "bolstering triggers on enemy death" do
      context = %{
        nearby_enemies: [101, 102, 103]
      }

      effects = Affix.process_trigger(:enemy_death, [3], context)

      assert length(effects) == 3
      assert Enum.all?(effects, &(&1.type == :buff))
      assert Enum.all?(effects, &(&1.buff_id == :bolstering))
    end

    test "raging triggers at low health" do
      context = %{
        enemy_id: 101,
        health_percent: 25
      }

      effects = Affix.process_trigger(:low_health, [4], context)

      assert length(effects) == 1
      assert hd(effects).buff_id == :enrage
    end

    test "raging doesn't trigger above 30%" do
      context = %{
        enemy_id: 101,
        health_percent: 50
      }

      effects = Affix.process_trigger(:low_health, [4], context)

      assert effects == []
    end

    test "sanguine spawns healing pool on death" do
      context = %{
        position: {100.0, 200.0, 0.0}
      }

      effects = Affix.process_trigger(:enemy_death, [5], context)

      assert length(effects) == 1
      assert hd(effects).type == :spawn_hazard
      assert hd(effects).hazard_type == :healing_pool
    end

    test "unrelated triggers don't produce effects" do
      # Bolstering only triggers on enemy_death, not low_health
      effects = Affix.process_trigger(:low_health, [3], %{})

      assert effects == []
    end
  end
end
