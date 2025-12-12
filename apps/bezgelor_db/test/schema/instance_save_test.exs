defmodule BezgelorDb.Schema.InstanceSaveTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.InstanceSave

  @valid_attrs %{
    instance_guid: <<1, 2, 3, 4, 5, 6, 7, 8>>,
    instance_definition_id: 100,
    difficulty: "veteran",
    created_at: DateTime.utc_now(),
    expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = InstanceSave.changeset(%InstanceSave{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without instance_guid" do
      attrs = Map.delete(@valid_attrs, :instance_guid)
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_guid
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "invalid without difficulty" do
      attrs = Map.delete(@valid_attrs, :difficulty)
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).difficulty
    end

    test "invalid without created_at" do
      attrs = Map.delete(@valid_attrs, :created_at)
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).created_at
    end

    test "invalid without expires_at" do
      attrs = Map.delete(@valid_attrs, :expires_at)
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).expires_at
    end

    test "invalid difficulty" do
      attrs = Map.put(@valid_attrs, :difficulty, "invalid")
      changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).difficulty
    end

    test "accepts all valid difficulties" do
      for diff <- ~w(normal veteran) do
        attrs = Map.put(@valid_attrs, :difficulty, diff)
        changeset = InstanceSave.changeset(%InstanceSave{}, attrs)
        assert changeset.valid?, "Expected #{diff} to be valid"
      end
    end

    test "defaults boss_kills to empty list" do
      changeset = InstanceSave.changeset(%InstanceSave{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :boss_kills) == []
    end

    test "defaults trash_cleared to empty list" do
      changeset = InstanceSave.changeset(%InstanceSave{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :trash_cleared) == []
    end
  end

  describe "record_boss_kill/2" do
    test "adds boss to kills list" do
      save = %InstanceSave{boss_kills: []}
      changeset = InstanceSave.record_boss_kill(save, 1)
      assert Ecto.Changeset.get_change(changeset, :boss_kills) == [1]
    end

    test "deduplicates boss kills" do
      save = %InstanceSave{boss_kills: [1, 2]}
      changeset = InstanceSave.record_boss_kill(save, 1)
      # When adding a duplicate, Enum.uniq prevents duplication
      # So the list remains [1, 2] - use get_field since list didn't change
      kills = Ecto.Changeset.get_field(changeset, :boss_kills)
      assert length(kills) == 2
      assert 1 in kills
      assert 2 in kills
    end

    test "preserves existing kills" do
      save = %InstanceSave{boss_kills: [1, 2]}
      changeset = InstanceSave.record_boss_kill(save, 3)
      kills = Ecto.Changeset.get_change(changeset, :boss_kills)
      assert 1 in kills
      assert 2 in kills
      assert 3 in kills
    end
  end

  describe "record_trash_cleared/2" do
    test "adds area to cleared list" do
      save = %InstanceSave{trash_cleared: []}
      changeset = InstanceSave.record_trash_cleared(save, "area_1")
      assert Ecto.Changeset.get_change(changeset, :trash_cleared) == ["area_1"]
    end

    test "deduplicates cleared areas" do
      save = %InstanceSave{trash_cleared: ["area_1", "area_2"]}
      changeset = InstanceSave.record_trash_cleared(save, "area_1")
      # When adding a duplicate, Enum.uniq prevents duplication
      # Use get_field since the list didn't actually change
      cleared = Ecto.Changeset.get_field(changeset, :trash_cleared)
      assert length(cleared) == 2
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is in the future" do
      save = %InstanceSave{expires_at: DateTime.add(DateTime.utc_now(), 1, :day)}
      refute InstanceSave.expired?(save)
    end

    test "returns true when expires_at is in the past" do
      save = %InstanceSave{expires_at: DateTime.add(DateTime.utc_now(), -1, :day)}
      assert InstanceSave.expired?(save)
    end
  end

  describe "boss_killed?/2" do
    test "returns true when boss is in kills list" do
      save = %InstanceSave{boss_kills: [1, 2, 3]}
      assert InstanceSave.boss_killed?(save, 2)
    end

    test "returns false when boss is not in kills list" do
      save = %InstanceSave{boss_kills: [1, 2, 3]}
      refute InstanceSave.boss_killed?(save, 5)
    end

    test "returns false when kills list is empty" do
      save = %InstanceSave{boss_kills: []}
      refute InstanceSave.boss_killed?(save, 1)
    end
  end

  describe "trash_area_cleared?/2" do
    test "returns true when area is in cleared list" do
      save = %InstanceSave{trash_cleared: ["area_1", "area_2"]}
      assert InstanceSave.trash_area_cleared?(save, "area_1")
    end

    test "returns false when area is not in cleared list" do
      save = %InstanceSave{trash_cleared: ["area_1", "area_2"]}
      refute InstanceSave.trash_area_cleared?(save, "area_3")
    end
  end

  describe "bosses_killed_count/1" do
    test "returns count of killed bosses" do
      save = %InstanceSave{boss_kills: [1, 2, 3]}
      assert InstanceSave.bosses_killed_count(save) == 3
    end

    test "returns 0 for empty list" do
      save = %InstanceSave{boss_kills: []}
      assert InstanceSave.bosses_killed_count(save) == 0
    end
  end

  describe "progress/2" do
    test "returns progress as fraction" do
      save = %InstanceSave{boss_kills: [1, 2]}
      assert InstanceSave.progress(save, 5) == 0.4
    end

    test "returns 1.0 when all bosses killed" do
      save = %InstanceSave{boss_kills: [1, 2, 3, 4, 5]}
      assert InstanceSave.progress(save, 5) == 1.0
    end

    test "returns 0.0 for zero total bosses" do
      save = %InstanceSave{boss_kills: [1, 2]}
      assert InstanceSave.progress(save, 0) == 0.0
    end

    test "returns 0.0 for empty kills" do
      save = %InstanceSave{boss_kills: []}
      assert InstanceSave.progress(save, 5) == 0.0
    end
  end
end
