defmodule BezgelorDb.Schema.MythicRunTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.MythicRun

  @valid_attrs %{
    instance_definition_id: 100,
    level: 10,
    affixes: ["fortified", "bolstering"],
    duration_seconds: 1200,
    timed: true,
    completed_at: DateTime.utc_now(),
    member_ids: [1, 2, 3, 4, 5],
    member_names: ["Tank", "Healer", "DPS1", "DPS2", "DPS3"],
    member_classes: ["warrior", "medic", "spellslinger", "stalker", "esper"]
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = MythicRun.changeset(%MythicRun{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "invalid without level" do
      attrs = Map.delete(@valid_attrs, :level)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).level
    end

    test "invalid without affixes" do
      attrs = Map.delete(@valid_attrs, :affixes)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).affixes
    end

    test "invalid without duration_seconds" do
      attrs = Map.delete(@valid_attrs, :duration_seconds)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration_seconds
    end

    test "invalid without timed" do
      attrs = Map.delete(@valid_attrs, :timed)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).timed
    end

    test "invalid without completed_at" do
      attrs = Map.delete(@valid_attrs, :completed_at)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).completed_at
    end

    test "invalid without member_ids" do
      attrs = Map.delete(@valid_attrs, :member_ids)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).member_ids
    end

    test "invalid without member_names" do
      attrs = Map.delete(@valid_attrs, :member_names)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).member_names
    end

    test "invalid without member_classes" do
      attrs = Map.delete(@valid_attrs, :member_classes)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).member_classes
    end

    test "validates level greater than 0" do
      attrs = Map.put(@valid_attrs, :level, 0)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
    end

    test "validates duration_seconds greater than 0" do
      attrs = Map.put(@valid_attrs, :duration_seconds, 0)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
    end

    test "validates season greater than 0" do
      attrs = Map.put(@valid_attrs, :season, 0)
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
    end

    test "defaults season to 1" do
      changeset = MythicRun.changeset(%MythicRun{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :season) == 1
    end

    test "validates member_ids minimum length" do
      attrs = Map.put(@valid_attrs, :member_ids, [])
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
    end

    test "validates member_ids maximum length" do
      attrs = Map.put(@valid_attrs, :member_ids, [1, 2, 3, 4, 5, 6])
      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
    end

    test "validates member arrays match length" do
      attrs =
        Map.merge(@valid_attrs, %{
          member_ids: [1, 2, 3],
          member_names: ["A", "B"],
          member_classes: ["warrior", "medic", "stalker"]
        })

      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      refute changeset.valid?
      assert "member arrays must have matching lengths" in errors_on(changeset).member_ids
    end

    test "accepts matching member arrays" do
      attrs =
        Map.merge(@valid_attrs, %{
          member_ids: [1, 2, 3],
          member_names: ["A", "B", "C"],
          member_classes: ["warrior", "medic", "stalker"]
        })

      changeset = MythicRun.changeset(%MythicRun{}, attrs)
      assert changeset.valid?
    end
  end

  describe "timed?/1" do
    test "returns true when timed" do
      run = %MythicRun{timed: true}
      assert MythicRun.timed?(run)
    end

    test "returns false when not timed" do
      run = %MythicRun{timed: false}
      refute MythicRun.timed?(run)
    end
  end

  describe "formatted_duration/1" do
    test "formats seconds as MM:SS" do
      run = %MythicRun{duration_seconds: 1800}
      assert MythicRun.formatted_duration(run) == "30:00"
    end

    test "pads single-digit values" do
      run = %MythicRun{duration_seconds: 65}
      assert MythicRun.formatted_duration(run) == "01:05"
    end

    test "handles zero" do
      run = %MythicRun{duration_seconds: 0}
      assert MythicRun.formatted_duration(run) == "00:00"
    end
  end

  describe "score/2" do
    test "calculates base score from level" do
      run = %MythicRun{level: 10, duration_seconds: 1800, timed: false}
      score = MythicRun.score(run, 1800)
      assert score == 1000
    end

    test "adds time bonus for timed runs" do
      run = %MythicRun{level: 10, duration_seconds: 900, timed: true}
      # 900 seconds with 1800 limit = 50% remaining = 25 bonus
      score = MythicRun.score(run, 1800)
      assert score == 1025.0
    end

    test "no bonus for untimed runs" do
      run = %MythicRun{level: 10, duration_seconds: 900, timed: false}
      score = MythicRun.score(run, 1800)
      assert score == 1000
    end
  end

  describe "members/1" do
    test "returns zipped member data" do
      run = %MythicRun{
        member_ids: [1, 2, 3],
        member_names: ["Tank", "Healer", "DPS"],
        member_classes: ["warrior", "medic", "stalker"]
      }

      members = MythicRun.members(run)

      assert members == [
               {1, "Tank", "warrior"},
               {2, "Healer", "medic"},
               {3, "DPS", "stalker"}
             ]
    end
  end
end
