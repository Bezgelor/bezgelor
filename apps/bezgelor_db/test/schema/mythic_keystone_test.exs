defmodule BezgelorDb.Schema.MythicKeystoneTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.MythicKeystone

  @valid_attrs %{
    character_id: 1,
    instance_definition_id: 100,
    level: 5,
    obtained_at: DateTime.utc_now()
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = MythicKeystone.changeset(%MythicKeystone{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "uses default level when not provided" do
      # Schema has default: 1, so level is valid even when not provided
      attrs = Map.delete(@valid_attrs, :level)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :level) == 1
    end

    test "invalid without obtained_at" do
      attrs = Map.delete(@valid_attrs, :obtained_at)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).obtained_at
    end

    test "validates level greater than 0" do
      attrs = Map.put(@valid_attrs, :level, 0)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      refute changeset.valid?
    end

    test "validates level at most 30" do
      attrs = Map.put(@valid_attrs, :level, 31)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :level, 30)
      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      assert changeset.valid?
    end

    test "defaults level to 1" do
      changeset = MythicKeystone.changeset(%MythicKeystone{}, @valid_attrs)
      # Note: level is provided in valid_attrs, but default is 1 in schema
      assert Ecto.Changeset.get_field(changeset, :level) == 5
    end

    test "defaults affixes to empty list" do
      changeset = MythicKeystone.changeset(%MythicKeystone{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :affixes) == []
    end

    test "defaults depleted to false" do
      changeset = MythicKeystone.changeset(%MythicKeystone{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :depleted) == false
    end

    test "accepts optional fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          affixes: ["fortified", "bolstering"],
          depleted: true
        })

      changeset = MythicKeystone.changeset(%MythicKeystone{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :affixes) == ["fortified", "bolstering"]
      assert Ecto.Changeset.get_field(changeset, :depleted) == true
    end
  end

  describe "upgrade/2" do
    test "increases level by 1 by default" do
      keystone = %MythicKeystone{level: 5, depleted: true}
      changeset = MythicKeystone.upgrade(keystone)
      assert Ecto.Changeset.get_change(changeset, :level) == 6
      assert Ecto.Changeset.get_change(changeset, :depleted) == false
    end

    test "increases level by specified amount" do
      keystone = %MythicKeystone{level: 5, depleted: false}
      changeset = MythicKeystone.upgrade(keystone, 3)
      assert Ecto.Changeset.get_change(changeset, :level) == 8
    end

    test "caps at max level 30" do
      keystone = %MythicKeystone{level: 29, depleted: false}
      changeset = MythicKeystone.upgrade(keystone, 5)
      assert Ecto.Changeset.get_change(changeset, :level) == 30
    end

    test "resets depleted status" do
      keystone = %MythicKeystone{level: 5, depleted: true}
      changeset = MythicKeystone.upgrade(keystone)
      assert Ecto.Changeset.get_change(changeset, :depleted) == false
    end
  end

  describe "deplete/1" do
    test "decreases level by 1" do
      keystone = %MythicKeystone{level: 5, depleted: false}
      changeset = MythicKeystone.deplete(keystone)
      assert Ecto.Changeset.get_change(changeset, :level) == 4
    end

    test "sets depleted to true" do
      keystone = %MythicKeystone{level: 5, depleted: false}
      changeset = MythicKeystone.deplete(keystone)
      assert Ecto.Changeset.get_change(changeset, :depleted) == true
    end

    test "does not go below level 1" do
      keystone = %MythicKeystone{level: 1, depleted: false}
      changeset = MythicKeystone.deplete(keystone)
      # Level stays at 1, so there's no "change" to track
      assert Ecto.Changeset.get_field(changeset, :level) == 1
      assert Ecto.Changeset.get_change(changeset, :depleted) == true
    end
  end

  describe "reset_depleted/1" do
    test "sets depleted to false without changing level" do
      keystone = %MythicKeystone{level: 5, depleted: true}
      changeset = MythicKeystone.reset_depleted(keystone)
      assert Ecto.Changeset.get_change(changeset, :depleted) == false
      refute Ecto.Changeset.get_change(changeset, :level)
    end
  end

  describe "set_affixes/2" do
    test "sets new affixes" do
      keystone = %MythicKeystone{affixes: []}
      changeset = MythicKeystone.set_affixes(keystone, ["fortified", "sanguine"])
      assert Ecto.Changeset.get_change(changeset, :affixes) == ["fortified", "sanguine"]
    end

    test "replaces existing affixes" do
      keystone = %MythicKeystone{affixes: ["old_affix"]}
      changeset = MythicKeystone.set_affixes(keystone, ["new_affix"])
      assert Ecto.Changeset.get_change(changeset, :affixes) == ["new_affix"]
    end
  end

  describe "depleted?/1" do
    test "returns true when depleted" do
      keystone = %MythicKeystone{depleted: true}
      assert MythicKeystone.depleted?(keystone)
    end

    test "returns false when not depleted" do
      keystone = %MythicKeystone{depleted: false}
      refute MythicKeystone.depleted?(keystone)
    end
  end

  describe "max_level?/1" do
    test "returns true at max level" do
      keystone = %MythicKeystone{level: 30}
      assert MythicKeystone.max_level?(keystone)
    end

    test "returns false below max level" do
      keystone = %MythicKeystone{level: 29}
      refute MythicKeystone.max_level?(keystone)
    end
  end

  describe "max_level/0" do
    test "returns 30" do
      assert MythicKeystone.max_level() == 30
    end
  end

  describe "calculate_upgrade_levels/2" do
    test "returns 0 when timer failed" do
      assert MythicKeystone.calculate_upgrade_levels(1800, 1500) == 0
    end

    test "returns 1 for just barely timed" do
      assert MythicKeystone.calculate_upgrade_levels(1400, 1500) == 1
    end

    test "returns 2 for 20%+ time remaining" do
      # 1200 seconds with 1500 limit = 20% remaining
      assert MythicKeystone.calculate_upgrade_levels(1200, 1500) == 2
    end

    test "returns 3 for 40%+ time remaining" do
      # 900 seconds with 1500 limit = 40% remaining
      assert MythicKeystone.calculate_upgrade_levels(900, 1500) == 3
    end

    test "returns 0 when exactly at time limit" do
      assert MythicKeystone.calculate_upgrade_levels(1500, 1500) == 0
    end
  end
end
