defmodule BezgelorDb.Schema.LootHistoryTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.LootHistory

  @valid_attrs %{
    item_id: 12345,
    awarded_at: DateTime.utc_now()
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = LootHistory.changeset(%LootHistory{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without item_id" do
      attrs = Map.delete(@valid_attrs, :item_id)
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).item_id
    end

    test "invalid without awarded_at" do
      attrs = Map.delete(@valid_attrs, :awarded_at)
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).awarded_at
    end

    test "invalid source_type" do
      attrs = Map.put(@valid_attrs, :source_type, "invalid")
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).source_type
    end

    test "invalid distribution_method" do
      attrs = Map.put(@valid_attrs, :distribution_method, "invalid")
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).distribution_method
    end

    test "accepts all valid source types" do
      for type <- ~w(boss trash chest) do
        attrs = Map.put(@valid_attrs, :source_type, type)
        changeset = LootHistory.changeset(%LootHistory{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "accepts all valid distribution methods" do
      for method <- ~w(personal need greed master round_robin) do
        attrs = Map.put(@valid_attrs, :distribution_method, method)
        changeset = LootHistory.changeset(%LootHistory{}, attrs)
        assert changeset.valid?, "Expected #{method} to be valid"
      end
    end

    test "validates roll_value range" do
      attrs = Map.put(@valid_attrs, :roll_value, 0)
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :roll_value, 101)
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :roll_value, 50)
      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      assert changeset.valid?
    end

    test "accepts all optional fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          instance_guid: <<1, 2, 3, 4, 5, 6, 7, 8>>,
          character_id: 1,
          item_quality: "epic",
          source_type: "boss",
          source_id: 500,
          distribution_method: "need",
          roll_value: 95
        })

      changeset = LootHistory.changeset(%LootHistory{}, attrs)
      assert changeset.valid?
    end
  end

  describe "record_drop/1" do
    test "creates a loot history entry with current time" do
      attrs = %{item_id: 12345}
      changeset = LootHistory.record_drop(attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :item_id) == 12345
      assert Ecto.Changeset.get_field(changeset, :awarded_at) != nil
    end

    test "merges provided attributes" do
      attrs = %{item_id: 12345, source_type: "boss", source_id: 500}
      changeset = LootHistory.record_drop(attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :source_type) == "boss"
      assert Ecto.Changeset.get_field(changeset, :source_id) == 500
    end
  end

  describe "source type checks" do
    test "from_boss?/1 returns true for boss loot" do
      assert LootHistory.from_boss?(%LootHistory{source_type: "boss"})
      refute LootHistory.from_boss?(%LootHistory{source_type: "trash"})
    end

    test "from_trash?/1 returns true for trash loot" do
      assert LootHistory.from_trash?(%LootHistory{source_type: "trash"})
      refute LootHistory.from_trash?(%LootHistory{source_type: "boss"})
    end

    test "from_chest?/1 returns true for chest loot" do
      assert LootHistory.from_chest?(%LootHistory{source_type: "chest"})
      refute LootHistory.from_chest?(%LootHistory{source_type: "boss"})
    end
  end

  describe "distribution method checks" do
    test "personal_loot?/1 returns true for personal loot" do
      assert LootHistory.personal_loot?(%LootHistory{distribution_method: "personal"})
      refute LootHistory.personal_loot?(%LootHistory{distribution_method: "need"})
    end

    test "need_roll?/1 returns true for need roll" do
      assert LootHistory.need_roll?(%LootHistory{distribution_method: "need"})
      refute LootHistory.need_roll?(%LootHistory{distribution_method: "greed"})
    end

    test "greed_roll?/1 returns true for greed roll" do
      assert LootHistory.greed_roll?(%LootHistory{distribution_method: "greed"})
      refute LootHistory.greed_roll?(%LootHistory{distribution_method: "need"})
    end

    test "master_loot?/1 returns true for master loot" do
      assert LootHistory.master_loot?(%LootHistory{distribution_method: "master"})
      refute LootHistory.master_loot?(%LootHistory{distribution_method: "personal"})
    end
  end

  describe "unclaimed?/1" do
    test "returns true when character_id is nil" do
      assert LootHistory.unclaimed?(%LootHistory{character_id: nil})
    end

    test "returns false when character_id is set" do
      refute LootHistory.unclaimed?(%LootHistory{character_id: 1})
    end
  end

  describe "constants" do
    test "source_types/0 returns list of valid source types" do
      types = LootHistory.source_types()
      assert "boss" in types
      assert "trash" in types
      assert "chest" in types
    end

    test "distribution_methods/0 returns list of valid distribution methods" do
      methods = LootHistory.distribution_methods()
      assert "personal" in methods
      assert "need" in methods
      assert "greed" in methods
      assert "master" in methods
      assert "round_robin" in methods
    end
  end
end
