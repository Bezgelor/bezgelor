defmodule BezgelorDb.Schema.InstanceLockoutTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.InstanceLockout

  @valid_attrs %{
    character_id: 1,
    instance_type: "dungeon",
    instance_definition_id: 100,
    difficulty: "veteran",
    expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = InstanceLockout.changeset(%InstanceLockout{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without instance_type" do
      attrs = Map.delete(@valid_attrs, :instance_type)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_type
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "invalid without difficulty" do
      attrs = Map.delete(@valid_attrs, :difficulty)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).difficulty
    end

    test "invalid without expires_at" do
      attrs = Map.delete(@valid_attrs, :expires_at)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).expires_at
    end

    test "invalid instance_type" do
      attrs = Map.put(@valid_attrs, :instance_type, "invalid")
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).instance_type
    end

    test "invalid difficulty" do
      attrs = Map.put(@valid_attrs, :difficulty, "invalid")
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).difficulty
    end

    test "accepts all valid instance types" do
      for type <- ~w(dungeon adventure raid expedition) do
        attrs = Map.put(@valid_attrs, :instance_type, type)
        changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "accepts all valid difficulties" do
      for diff <- ~w(normal veteran challenge mythic_plus) do
        attrs = Map.put(@valid_attrs, :difficulty, diff)
        changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
        assert changeset.valid?, "Expected #{diff} to be valid"
      end
    end

    test "defaults boss_kills to empty list" do
      changeset = InstanceLockout.changeset(%InstanceLockout{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :boss_kills) == []
    end

    test "defaults loot_eligible to true" do
      changeset = InstanceLockout.changeset(%InstanceLockout{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :loot_eligible) == true
    end

    test "defaults diminishing_factor to 1.0" do
      changeset = InstanceLockout.changeset(%InstanceLockout{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :diminishing_factor) == 1.0
    end

    test "validates diminishing_factor is positive" do
      attrs = Map.put(@valid_attrs, :diminishing_factor, 0.0)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
    end

    test "validates diminishing_factor is at most 1.0" do
      attrs = Map.put(@valid_attrs, :diminishing_factor, 1.5)
      changeset = InstanceLockout.changeset(%InstanceLockout{}, attrs)
      refute changeset.valid?
    end
  end

  describe "record_boss_kill/2" do
    test "adds boss to kills list" do
      lockout = %InstanceLockout{boss_kills: []}
      changeset = InstanceLockout.record_boss_kill(lockout, 1)
      assert Ecto.Changeset.get_change(changeset, :boss_kills) == [1]
    end

    test "does not duplicate boss kills" do
      lockout = %InstanceLockout{boss_kills: [1, 2]}
      changeset = InstanceLockout.record_boss_kill(lockout, 1)
      # When adding a duplicate, Enum.uniq prevents duplication
      # So the list remains [1, 2] and there's no "change"
      kills = Ecto.Changeset.get_field(changeset, :boss_kills)
      assert length(kills) == 2
      assert 1 in kills
      assert 2 in kills
    end

    test "preserves existing kills" do
      lockout = %InstanceLockout{boss_kills: [1, 2]}
      changeset = InstanceLockout.record_boss_kill(lockout, 3)
      kills = Ecto.Changeset.get_change(changeset, :boss_kills)
      assert 1 in kills
      assert 2 in kills
      assert 3 in kills
    end
  end

  describe "record_loot_received/1" do
    test "sets loot_eligible to false" do
      lockout = %InstanceLockout{loot_eligible: true}
      changeset = InstanceLockout.record_loot_received(lockout)
      assert Ecto.Changeset.get_change(changeset, :loot_eligible) == false
    end

    test "sets loot_received_at" do
      lockout = %InstanceLockout{loot_eligible: true}
      changeset = InstanceLockout.record_loot_received(lockout)
      assert Ecto.Changeset.get_change(changeset, :loot_received_at) != nil
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is in the future" do
      lockout = %InstanceLockout{expires_at: DateTime.add(DateTime.utc_now(), 1, :day)}
      refute InstanceLockout.expired?(lockout)
    end

    test "returns true when expires_at is in the past" do
      lockout = %InstanceLockout{expires_at: DateTime.add(DateTime.utc_now(), -1, :day)}
      assert InstanceLockout.expired?(lockout)
    end
  end

  describe "boss_killed?/2" do
    test "returns true when boss is in kills list" do
      lockout = %InstanceLockout{boss_kills: [1, 2, 3]}
      assert InstanceLockout.boss_killed?(lockout, 2)
    end

    test "returns false when boss is not in kills list" do
      lockout = %InstanceLockout{boss_kills: [1, 2, 3]}
      refute InstanceLockout.boss_killed?(lockout, 5)
    end

    test "returns false when kills list is empty" do
      lockout = %InstanceLockout{boss_kills: []}
      refute InstanceLockout.boss_killed?(lockout, 1)
    end
  end

  describe "instance_types/0" do
    test "returns list of valid instance types" do
      types = InstanceLockout.instance_types()
      assert "dungeon" in types
      assert "adventure" in types
      assert "raid" in types
      assert "expedition" in types
    end
  end

  describe "difficulties/0" do
    test "returns list of valid difficulties" do
      diffs = InstanceLockout.difficulties()
      assert "normal" in diffs
      assert "veteran" in diffs
      assert "challenge" in diffs
      assert "mythic_plus" in diffs
    end
  end
end
