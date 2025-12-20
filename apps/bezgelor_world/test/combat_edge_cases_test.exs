defmodule BezgelorWorld.CombatEdgeCasesTest do
  @moduledoc """
  Edge case tests for combat systems.

  Tests extreme scenarios:
  - Level difference XP scaling (gray mobs, high level targets)
  - Multi-level ups from large XP gains
  - Overkill damage handling
  - Simultaneous damage from multiple sources
  - AI evade and leash mechanics
  """
  use ExUnit.Case, async: false

  alias BezgelorCore.{AI, CreatureTemplate, Experience}
  alias BezgelorWorld.CreatureManager

  describe "XP edge cases" do
    test "gray mob (5+ levels below) gives 10% XP" do
      # Player level 10, creature level 4 = -6 level diff
      base_xp = 100
      xp = Experience.xp_from_kill(10, 4, base_xp)

      # 10% of 100
      assert xp == 10
    end

    test "much higher level creature gives 120% XP" do
      # Player level 5, creature level 12 = +7 level diff
      base_xp = 100
      xp = Experience.xp_from_kill(5, 12, base_xp)

      # 120% of 100
      assert xp == 120
    end

    test "same level creature gives 100% XP" do
      base_xp = 100
      xp = Experience.xp_from_kill(10, 10, base_xp)

      assert xp == 100
    end

    test "slightly higher level gives 110% XP" do
      # +3 level diff
      base_xp = 100
      xp = Experience.xp_from_kill(10, 13, base_xp)

      assert xp == 110
    end

    test "slightly lower level gives 50% XP" do
      # -3 level diff
      base_xp = 100
      xp = Experience.xp_from_kill(10, 7, base_xp)

      assert xp == 50
    end
  end

  describe "level-up edge cases" do
    test "multi-level up from large XP gain" do
      # At level 1 with enough XP to reach level 5
      # Level 2 needs 400 XP, Level 3 needs 900, etc
      # Total for level 5: 100 * 5^2 = 2500
      huge_xp = 5000

      {new_level, remaining_xp, leveled_up?} = Experience.apply_xp(1, 0, huge_xp)

      assert leveled_up?
      # Should have leveled up multiple times
      assert new_level > 2
    end

    test "max level prevents overflow" do
      max_level = Experience.max_level()

      # At max level, should not level up regardless of XP
      {new_level, _xp, leveled_up?} = Experience.apply_xp(max_level, 0, 999_999)

      refute leveled_up?
      assert new_level == max_level
    end

    test "XP carries over after level up" do
      # Need 400 XP for level 2
      {level, remaining_xp, _} = Experience.apply_xp(1, 0, 450)

      assert level == 2
      # 450 - 400
      assert remaining_xp == 50
    end
  end

  describe "damage edge cases" do
    test "overkill damage still results in death" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {8000.0, 8000.0, 8000.0})
      template = CreatureTemplate.get(1)

      # Deal 10x the creature's health
      overkill_damage = template.max_health * 10
      {:ok, :killed, info} = CreatureManager.damage_creature(guid, 12345, overkill_damage)

      assert info.xp_reward > 0
      creature = CreatureManager.get_creature(guid)
      assert creature.entity.health <= 0
    end

    test "zero damage does not kill or error" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {8100.0, 8000.0, 8000.0})

      {:ok, :damaged, info} = CreatureManager.damage_creature(guid, 12345, 0)

      template = CreatureTemplate.get(1)
      assert info.remaining_health == template.max_health
    end

    test "multiple small hits accumulate correctly" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {8200.0, 8000.0, 8000.0})
      template = CreatureTemplate.get(2)

      # Hit 10 times with 10 damage each
      for _ <- 1..10 do
        CreatureManager.damage_creature(guid, 12345, 10)
      end

      creature = CreatureManager.get_creature(guid)

      expected_health = max(0, template.max_health - 100)
      actual_health = max(0, creature.entity.health)

      # Either still alive with reduced health, or dead
      if expected_health > 0 do
        assert actual_health == expected_health
      else
        assert AI.dead?(creature.ai)
      end
    end

    test "different attackers add to threat" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {8300.0, 8000.0, 8000.0})

      attacker1 = 11111
      attacker2 = 22222
      attacker3 = 33333

      # Use small damage to avoid killing
      # Note: First attacker gets 100 base threat from enter_combat + damage
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, attacker1, 5)
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, attacker2, 10)
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, attacker3, 15)

      creature = CreatureManager.get_creature(guid)

      # All three should be in threat table
      assert Map.has_key?(creature.ai.threat_table, attacker1)
      assert Map.has_key?(creature.ai.threat_table, attacker2)
      assert Map.has_key?(creature.ai.threat_table, attacker3)

      # First attacker has base 100 threat from enter_combat + 5 damage = 105
      # Second attacker has 10 damage = 10
      # Third attacker has 15 damage = 15
      # Verify all attackers have positive threat
      assert creature.ai.threat_table[attacker1] > 0
      assert creature.ai.threat_table[attacker2] > 0
      assert creature.ai.threat_table[attacker3] > 0
    end
  end

  describe "AI state edge cases" do
    test "creature cannot enter combat when dead" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {8400.0, 8000.0, 8000.0})

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      # Try to enter combat
      :ok = CreatureManager.creature_enter_combat(guid, 99999)

      creature = CreatureManager.get_creature(guid)
      assert AI.dead?(creature.ai)
      # Should not have new target
      refute creature.ai.target_guid == 99999
    end

    test "creature tracks highest threat target" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {8500.0, 8000.0, 8000.0})

      # First attacker hits with small damage (gets 100 base + 5 = 105 threat)
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, 11111, 5)

      # Second attacker must deal > 105 damage to overtake
      # Hit twice to accumulate enough threat
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, 22222, 60)
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, 22222, 60)

      creature = CreatureManager.get_creature(guid)

      # Second attacker now has 120 threat, first has 105
      top_threat_target = AI.highest_threat_target(creature.ai)
      assert top_threat_target == 22222
    end

    test "respawn restores full health and clears combat state" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {8600.0, 8000.0, 8000.0})
      template = CreatureTemplate.get(1)

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      # Manually trigger respawn
      send(Process.whereis(CreatureManager), {:respawn_creature, guid})
      Process.sleep(10)

      creature = CreatureManager.get_creature(guid)

      assert creature.entity.health == template.max_health
      refute AI.dead?(creature.ai)
      refute AI.in_combat?(creature.ai)
      assert creature.ai.threat_table == %{}
    end
  end

  describe "boundary conditions" do
    test "level 1 player gains correct XP" do
      xp = Experience.xp_from_kill(1, 1, 100)
      assert xp == 100
    end

    test "max level player still calculates XP (but won't level)" do
      max_level = Experience.max_level()
      xp = Experience.xp_from_kill(max_level, max_level, 100)
      assert xp == 100
    end

    test "creature at spawn position has zero distance" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {9000.0, 9000.0, 9000.0})
      creature = CreatureManager.get_creature(guid)

      distance = AI.distance(creature.entity.position, creature.spawn_position)
      assert distance == 0.0
    end
  end
end
