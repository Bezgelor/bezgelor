defmodule BezgelorWorld.InstanceIntegrationTest do
  @moduledoc """
  Integration tests for the full dungeon/instance system.

  Tests the complete flow from group finder to instance completion.
  """

  use ExUnit.Case

  alias BezgelorWorld.GroupFinder.Matcher
  alias BezgelorWorld.Loot.LootRules
  alias BezgelorWorld.MythicPlus.{Keystone, Affix}

  describe "full dungeon queue to completion flow" do
    test "group finder forms valid 5-player dungeon group" do
      # Simulate 10 players queuing
      queue = [
        %{
          character_id: 1,
          roles: [:tank],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 510,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 490,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 505,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 495,
          language: "en"
        },
        %{
          character_id: 6,
          roles: [:tank],
          queued_at: 5,
          instance_ids: [100],
          gear_score: 520,
          language: "en"
        },
        %{
          character_id: 7,
          roles: [:healer],
          queued_at: 6,
          instance_ids: [100],
          gear_score: 515,
          language: "en"
        },
        %{
          character_id: 8,
          roles: [:dps],
          queued_at: 7,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 9,
          roles: [:dps],
          queued_at: 8,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 10,
          roles: [:dps],
          queued_at: 9,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      # First match should take first 5 eligible players
      {:ok, match} = Matcher.find_dungeon_match(:normal, queue)

      # Verify match composition
      assert length(match.members) == 5
      roles = Enum.map(match.members, & &1.role)
      assert :tank in roles
      assert :healer in roles
      assert Enum.count(roles, &(&1 == :dps)) == 3

      # Second match should form from remaining players
      remaining =
        Enum.reject(queue, fn p ->
          p.character_id in Enum.map(match.members, & &1.character_id)
        end)

      {:ok, match2} = Matcher.find_dungeon_match(:normal, remaining)
      assert length(match2.members) == 5
    end
  end

  describe "raid composition requirements" do
    test "raid requires proper tank/healer/dps ratio" do
      # Build a full raid queue (20 players)
      tanks =
        for i <- 1..2 do
          %{
            character_id: i,
            roles: [:tank],
            queued_at: i,
            instance_ids: [200],
            gear_score: 550,
            language: "en"
          }
        end

      healers =
        for i <- 3..7 do
          %{
            character_id: i,
            roles: [:healer],
            queued_at: i,
            instance_ids: [200],
            gear_score: 540,
            language: "en"
          }
        end

      dps =
        for i <- 8..20 do
          %{
            character_id: i,
            roles: [:dps],
            queued_at: i,
            instance_ids: [200],
            gear_score: 530,
            language: "en"
          }
        end

      queue = tanks ++ healers ++ dps

      {:ok, match} = Matcher.find_raid_match(:normal, queue)

      assert length(match.members) == 20
      roles = Enum.map(match.members, & &1.role)
      assert Enum.count(roles, &(&1 == :tank)) == 2
      assert Enum.count(roles, &(&1 == :healer)) == 5
      assert Enum.count(roles, &(&1 == :dps)) == 13
    end
  end

  describe "loot distribution scenarios" do
    test "need beats greed in rolls" do
      rolls = [
        %{character_id: 1, roll_type: :need, roll_value: 50},
        %{character_id: 2, roll_type: :greed, roll_value: 99},
        %{character_id: 3, roll_type: :pass, roll_value: 0}
      ]

      winner = LootRules.determine_winner(rolls)
      assert winner.character_id == 1
      assert winner.roll_type == :need
    end

    test "personal loot respects class restrictions" do
      warrior = %{class_id: 1}
      mage = %{class_id: 2}

      heavy_armor = %{
        id: 1,
        armor_type: :heavy,
        drop_chance: 100,
        bind_on_pickup: true
      }

      # Warrior can need on heavy armor
      assert LootRules.can_need?(warrior, heavy_armor)

      # Mage cannot need on heavy armor
      refute LootRules.can_need?(mage, heavy_armor)
    end
  end

  describe "mythic+ keystone progression" do
    test "keystone upgrades on timed completion" do
      keystone = Keystone.new(1, 100, 5)
      assert keystone.level == 5

      # +3 upgrade (under 60% of timer)
      upgraded = Keystone.upgrade(keystone, 3)
      assert upgraded.level == 8
      refute upgraded.depleted
    end

    test "keystone depletes on failed run" do
      keystone = Keystone.new(1, 100, 10)
      depleted = Keystone.deplete(keystone)

      assert depleted.level == 9
      assert depleted.depleted
    end

    test "affixes scale with keystone level" do
      key_low = Keystone.new(1, 100, 2)
      key_mid = Keystone.new(1, 100, 7)
      key_high = Keystone.new(1, 100, 15)

      # More affixes at higher levels
      assert length(key_low.affix_ids) >= 1
      assert length(key_mid.affix_ids) >= 3
      assert length(key_high.affix_ids) >= 4
    end
  end

  describe "affix mechanics" do
    test "fortified increases trash mob stats" do
      mods = Affix.get_stat_modifiers([1], :trash)

      # Fortified gives +30% health, +20% damage to trash
      assert mods.health_mult == 1.3
      assert mods.damage_mult == 1.2
    end

    test "tyrannical increases boss stats" do
      mods = Affix.get_stat_modifiers([2], :boss)

      # Tyrannical gives +40% health, +15% damage to bosses
      assert mods.health_mult == 1.4
      assert mods.damage_mult == 1.15
    end

    test "multiple affixes combine stat modifiers" do
      # Both Fortified and Tyrannical active (shouldn't happen but tests stacking)
      trash_mods = Affix.get_stat_modifiers([1, 2], :trash)
      boss_mods = Affix.get_stat_modifiers([1, 2], :boss)

      # Fortified affects trash
      assert trash_mods.health_mult >= 1.3

      # Tyrannical affects bosses
      assert boss_mods.health_mult >= 1.4
    end
  end

  describe "difficulty scaling" do
    test "veteran dungeon uses smart matching" do
      queue = [
        %{
          character_id: 1,
          roles: [:tank],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 600,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 580,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 620,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 590,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 610,
          language: "en"
        }
      ]

      {:ok, match} = Matcher.find_dungeon_match(:veteran, queue)

      # Veteran uses smart matching - should still form valid group
      assert length(match.members) == 5
    end

    test "loot method defaults correctly per content type" do
      # Modern content uses personal loot
      assert LootRules.default_method(:raid, :veteran) == :personal
      assert LootRules.default_method(:dungeon, :mythic_plus) == :personal

      # Normal dungeons use need before greed
      assert LootRules.default_method(:dungeon, :normal) == :need_before_greed
    end
  end

  describe "multi-role players" do
    test "players can fill multiple roles" do
      # Hybrid players who can tank or DPS
      queue = [
        %{
          character_id: 1,
          roles: [:tank, :dps],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:tank, :dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      {:ok, match} = Matcher.find_dungeon_match(:normal, queue)

      # One hybrid should be assigned tank, one should be assigned DPS
      roles = Enum.map(match.members, & &1.role)
      assert :tank in roles
      assert Enum.count(roles, &(&1 == :dps)) == 3
    end
  end
end
