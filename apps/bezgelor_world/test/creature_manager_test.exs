defmodule BezgelorWorld.CreatureManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager
  alias BezgelorCore.{AI, CreatureTemplate}

  # Note: Tests run against the application's running CreatureManager
  # Creatures spawned in tests persist between tests, but we use unique
  # positions and creature_count checks to verify behavior

  describe "spawn_creature/2" do
    test "spawns creature from template" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {100.0, 200.0, 300.0})

      assert is_integer(guid)
      assert guid > 0
    end

    test "returns error for unknown template" do
      {:error, :template_not_found} = CreatureManager.spawn_creature(999, {0.0, 0.0, 0.0})
    end

    test "creature has correct initial state" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {110.0, 220.0, 330.0})
      creature = CreatureManager.get_creature(guid)

      template = CreatureTemplate.get(2)

      assert creature.entity.name == template.name
      assert creature.entity.health == template.max_health
      assert creature.entity.position == {110.0, 220.0, 330.0}
      assert creature.spawn_position == {110.0, 220.0, 330.0}
      assert creature.ai.state == :idle
    end
  end

  describe "get_creature/1" do
    test "returns creature by GUID" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {200.0, 200.0, 200.0})
      creature = CreatureManager.get_creature(guid)

      assert creature != nil
      assert creature.entity.guid == guid
    end

    test "returns nil for unknown GUID" do
      assert nil == CreatureManager.get_creature(999_999_999)
    end
  end

  describe "list_creatures/0" do
    test "returns list of spawned creatures" do
      initial_count = CreatureManager.creature_count()
      {:ok, _} = CreatureManager.spawn_creature(1, {300.0, 300.0, 300.0})
      {:ok, _} = CreatureManager.spawn_creature(2, {310.0, 300.0, 300.0})

      creatures = CreatureManager.list_creatures()

      assert length(creatures) >= initial_count + 2
    end
  end

  describe "get_creatures_in_range/2" do
    test "returns creatures within range" do
      {:ok, _} = CreatureManager.spawn_creature(1, {1000.0, 1000.0, 1000.0})
      {:ok, _} = CreatureManager.spawn_creature(2, {1005.0, 1000.0, 1000.0})
      {:ok, _} = CreatureManager.spawn_creature(3, {1050.0, 1000.0, 1000.0})

      creatures = CreatureManager.get_creatures_in_range({1000.0, 1000.0, 1000.0}, 10.0)

      assert length(creatures) == 2
    end

    test "excludes dead creatures" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {2000.0, 2000.0, 2000.0})

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      creatures = CreatureManager.get_creatures_in_range({2000.0, 2000.0, 2000.0}, 10.0)

      # Dead creature should not be included
      refute Enum.any?(creatures, fn c -> c.entity.guid == guid end)
    end
  end

  describe "damage_creature/3" do
    test "reduces creature health" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {3000.0, 3000.0, 3000.0})

      {:ok, :damaged, info} = CreatureManager.damage_creature(guid, 12345, 50)

      template = CreatureTemplate.get(2)
      assert info.remaining_health == template.max_health - 50
    end

    test "creature enters combat when damaged" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {3100.0, 3000.0, 3000.0})

      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, 12345, 10)

      creature = CreatureManager.get_creature(guid)
      assert AI.in_combat?(creature.ai)
      assert creature.ai.target_guid == 12345
    end

    test "kills creature when damage exceeds health" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {3200.0, 3000.0, 3000.0})

      {:ok, :killed, info} = CreatureManager.damage_creature(guid, 12345, 1000)

      assert info.xp_reward > 0
      assert info.killer_guid == 12345

      creature = CreatureManager.get_creature(guid)
      assert AI.dead?(creature.ai)
    end

    test "returns error for unknown creature" do
      {:error, :creature_not_found} = CreatureManager.damage_creature(999_999_999, 12345, 50)
    end

    test "returns error for dead creature" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {3300.0, 3000.0, 3000.0})

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      # Try to damage again
      {:error, :creature_dead} = CreatureManager.damage_creature(guid, 12345, 50)
    end

    test "generates loot on kill" do
      # Cave Spider (id 2) has loot table
      {:ok, guid} = CreatureManager.spawn_creature(2, {3400.0, 3000.0, 3000.0})

      {:ok, :killed, info} = CreatureManager.damage_creature(guid, 12345, 1000)

      # Loot drops are random but should include gold (100% chance)
      assert info.gold >= 0
      assert is_list(info.items)
      assert is_list(info.loot_drops)
    end
  end

  describe "creature_enter_combat/2" do
    test "puts creature in combat" do
      {:ok, guid} = CreatureManager.spawn_creature(2, {4000.0, 4000.0, 4000.0})

      :ok = CreatureManager.creature_enter_combat(guid, 12345)

      creature = CreatureManager.get_creature(guid)
      assert AI.in_combat?(creature.ai)
    end
  end

  describe "creature_targetable?/1" do
    test "returns true for alive creatures" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {5000.0, 5000.0, 5000.0})

      assert CreatureManager.creature_targetable?(guid)
    end

    test "returns false for dead creatures" do
      {:ok, guid} = CreatureManager.spawn_creature(1, {5100.0, 5000.0, 5000.0})

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      refute CreatureManager.creature_targetable?(guid)
    end

    test "returns false for unknown creatures" do
      refute CreatureManager.creature_targetable?(999_999_999)
    end
  end

  describe "creature_count/0" do
    test "returns number of creatures" do
      initial_count = CreatureManager.creature_count()

      {:ok, _} = CreatureManager.spawn_creature(1, {6000.0, 6000.0, 6000.0})
      assert CreatureManager.creature_count() == initial_count + 1

      {:ok, _} = CreatureManager.spawn_creature(2, {6100.0, 6000.0, 6000.0})
      assert CreatureManager.creature_count() == initial_count + 2
    end
  end

  describe "respawning" do
    test "creature respawns after timer" do
      # Training dummy has 10 second respawn
      {:ok, guid} = CreatureManager.spawn_creature(1, {7000.0, 7000.0, 7000.0})

      # Kill the creature
      {:ok, :killed, _} = CreatureManager.damage_creature(guid, 12345, 1000)

      creature = CreatureManager.get_creature(guid)
      assert AI.dead?(creature.ai)

      # Manually trigger respawn (normally happens via timer)
      send(Process.whereis(CreatureManager), {:respawn_creature, guid})

      # Allow message to be processed
      Process.sleep(10)

      creature = CreatureManager.get_creature(guid)
      refute AI.dead?(creature.ai)
      assert creature.entity.health == creature.template.max_health
    end
  end
end
