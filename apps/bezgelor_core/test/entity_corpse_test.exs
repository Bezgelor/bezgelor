defmodule BezgelorCore.EntityCorpseTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Entity

  describe "corpse entities" do
    test "creates corpse entity from dead creature" do
      creature = %Entity{
        guid: 12345,
        type: :creature,
        name: "Test Mob",
        position: {10.0, 20.0, 30.0},
        display_info: 1001
      }

      corpse =
        Entity.create_corpse(creature, [
          # item_id, quantity
          {1001, 1},
          # gold (item_id 0)
          {0, 500}
        ])

      assert corpse.type == :corpse
      assert corpse.loot == [{1001, 1}, {0, 500}]
      assert corpse.source_guid == 12345
      assert corpse.position == creature.position
      assert corpse.name == "Test Mob"
      assert corpse.display_info == 1001
    end

    test "corpse has despawn timer" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [])

      assert corpse.despawn_at != nil
      assert corpse.despawn_at > System.monotonic_time(:millisecond)
    end

    test "corpse guid is different from source" do
      creature = %Entity{guid: 12345, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [])

      assert corpse.guid != creature.guid
    end
  end

  describe "has_loot_for?/2" do
    test "returns true when corpse has loot" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [{1001, 1}])

      assert Entity.has_loot_for?(corpse, 99999) == true
    end

    test "returns false when corpse has no loot" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [])

      assert Entity.has_loot_for?(corpse, 99999) == false
    end

    test "returns false for non-corpse entities" do
      creature = %Entity{guid: 1, type: :creature, position: {0.0, 0.0, 0.0}}

      assert Entity.has_loot_for?(creature, 99999) == false
    end
  end

  describe "take_loot/2" do
    test "returns loot items on first loot" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [{1001, 2}, {0, 100}])

      {_updated, loot} = Entity.take_loot(corpse, 99999)

      assert loot == [{1001, 2}, {0, 100}]
    end

    test "marks player as having looted" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [{1001, 1}])

      {updated, _loot} = Entity.take_loot(corpse, 99999)

      assert MapSet.member?(updated.looted_by, 99999)
    end

    test "returns empty list on second loot by same player" do
      creature = %Entity{guid: 1, position: {0.0, 0.0, 0.0}}
      corpse = Entity.create_corpse(creature, [{1001, 1}])

      {updated, _} = Entity.take_loot(corpse, 99999)
      {_, loot2} = Entity.take_loot(updated, 99999)

      assert loot2 == []
    end
  end

  describe "type conversions for corpse" do
    test "type_to_int returns 5 for corpse" do
      assert Entity.type_to_int(:corpse) == 5
    end

    test "int_to_type returns :corpse for 5" do
      assert Entity.int_to_type(5) == :corpse
    end
  end
end
