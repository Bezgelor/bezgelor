defmodule BezgelorWorld.CorpseManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.CorpseManager
  alias BezgelorCore.Entity

  setup do
    # Clear any corpses from previous tests
    CorpseManager.clear_all()
    :ok
  end

  describe "spawn_corpse/2" do
    test "creates corpse from creature with loot" do
      creature = %Entity{
        guid: 12345,
        type: :creature,
        name: "Test Creature",
        position: {100.0, 200.0, 300.0},
        display_info: 1001,
        zone_id: 10
      }

      loot = [{1001, 2}, {0, 500}]

      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, loot)

      assert is_integer(corpse_guid)
      assert corpse_guid != creature.guid
    end

    test "corpse can be retrieved by guid" do
      creature = %Entity{
        guid: 22222,
        type: :creature,
        name: "Test Mob",
        position: {50.0, 60.0, 70.0},
        display_info: 2002,
        zone_id: 5
      }

      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{100, 1}])

      {:ok, corpse} = CorpseManager.get_corpse(corpse_guid)

      assert corpse.type == :corpse
      assert corpse.name == "Test Mob"
      assert corpse.source_guid == 22222
      assert corpse.loot == [{100, 1}]
    end

    test "returns error for non-existent corpse" do
      assert {:error, :not_found} = CorpseManager.get_corpse(999_999)
    end
  end

  describe "take_loot/2" do
    test "returns loot for player on first loot" do
      creature = %Entity{guid: 11111, position: {0.0, 0.0, 0.0}, zone_id: 1}
      loot = [{1001, 3}, {1002, 1}, {0, 1000}]

      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, loot)

      {:ok, looted_items} = CorpseManager.take_loot(corpse_guid, 99999)

      assert looted_items == loot
    end

    test "returns empty list on second loot by same player" do
      creature = %Entity{guid: 33333, position: {0.0, 0.0, 0.0}, zone_id: 1}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{500, 1}])

      {:ok, _loot1} = CorpseManager.take_loot(corpse_guid, 88888)
      {:ok, loot2} = CorpseManager.take_loot(corpse_guid, 88888)

      assert loot2 == []
    end

    test "different players can each loot once" do
      creature = %Entity{guid: 44444, position: {0.0, 0.0, 0.0}, zone_id: 1}
      loot = [{999, 5}]
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, loot)

      {:ok, loot1} = CorpseManager.take_loot(corpse_guid, 11111)
      {:ok, loot2} = CorpseManager.take_loot(corpse_guid, 22222)

      assert loot1 == loot
      assert loot2 == loot
    end

    test "returns error for non-existent corpse" do
      assert {:error, :not_found} = CorpseManager.take_loot(888_888, 12345)
    end
  end

  describe "despawn_corpse/1" do
    test "removes corpse from manager" do
      creature = %Entity{guid: 55555, position: {0.0, 0.0, 0.0}, zone_id: 1}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1, 1}])

      :ok = CorpseManager.despawn_corpse(corpse_guid)

      assert {:error, :not_found} = CorpseManager.get_corpse(corpse_guid)
    end

    test "returns ok even for non-existent corpse" do
      assert :ok = CorpseManager.despawn_corpse(777_777)
    end
  end

  describe "get_corpses_in_zone/1" do
    test "returns all corpses in specified zone" do
      creature1 = %Entity{guid: 1001, position: {0.0, 0.0, 0.0}, zone_id: 100}
      creature2 = %Entity{guid: 1002, position: {0.0, 0.0, 0.0}, zone_id: 100}
      creature3 = %Entity{guid: 1003, position: {0.0, 0.0, 0.0}, zone_id: 200}

      {:ok, guid1} = CorpseManager.spawn_corpse(creature1, [])
      {:ok, guid2} = CorpseManager.spawn_corpse(creature2, [])
      {:ok, _guid3} = CorpseManager.spawn_corpse(creature3, [])

      corpses = CorpseManager.get_corpses_in_zone(100)

      assert length(corpses) == 2
      corpse_guids = Enum.map(corpses, & &1.guid)
      assert guid1 in corpse_guids
      assert guid2 in corpse_guids
    end

    test "returns empty list for zone with no corpses" do
      assert CorpseManager.get_corpses_in_zone(999) == []
    end
  end

  describe "has_loot_for?/2" do
    test "returns true when player hasn't looted yet" do
      creature = %Entity{guid: 66666, position: {0.0, 0.0, 0.0}, zone_id: 1}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1, 1}])

      assert CorpseManager.has_loot_for?(corpse_guid, 12345) == true
    end

    test "returns false after player has looted" do
      creature = %Entity{guid: 77777, position: {0.0, 0.0, 0.0}, zone_id: 1}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1, 1}])

      {:ok, _} = CorpseManager.take_loot(corpse_guid, 12345)

      assert CorpseManager.has_loot_for?(corpse_guid, 12345) == false
    end

    test "returns false for empty loot corpse" do
      creature = %Entity{guid: 88888, position: {0.0, 0.0, 0.0}, zone_id: 1}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [])

      assert CorpseManager.has_loot_for?(corpse_guid, 12345) == false
    end

    test "returns false for non-existent corpse" do
      assert CorpseManager.has_loot_for?(555_555, 12345) == false
    end
  end
end
