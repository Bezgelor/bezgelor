defmodule BezgelorDb.Schema.InstanceCompletionTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.InstanceCompletion

  @valid_attrs %{
    character_id: 1,
    instance_definition_id: 100,
    instance_type: "dungeon",
    difficulty: "veteran",
    completed_at: DateTime.utc_now()
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "invalid without instance_type" do
      attrs = Map.delete(@valid_attrs, :instance_type)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_type
    end

    test "invalid without difficulty" do
      attrs = Map.delete(@valid_attrs, :difficulty)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).difficulty
    end

    test "invalid without completed_at" do
      attrs = Map.delete(@valid_attrs, :completed_at)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).completed_at
    end

    test "invalid instance_type" do
      attrs = Map.put(@valid_attrs, :instance_type, "invalid")
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).instance_type
    end

    test "invalid difficulty" do
      attrs = Map.put(@valid_attrs, :difficulty, "invalid")
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).difficulty
    end

    test "accepts all valid instance types" do
      for type <- ~w(dungeon adventure raid expedition) do
        attrs = Map.put(@valid_attrs, :instance_type, type)
        changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "accepts all valid difficulties" do
      for diff <- ~w(normal veteran challenge mythic_plus) do
        attrs = Map.put(@valid_attrs, :difficulty, diff)
        changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
        assert changeset.valid?, "Expected #{diff} to be valid"
      end
    end

    test "defaults deaths to 0" do
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :deaths) == 0
    end

    test "defaults damage_done to 0" do
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :damage_done) == 0
    end

    test "defaults healing_done to 0" do
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :healing_done) == 0
    end

    test "validates deaths is non-negative" do
      attrs = Map.put(@valid_attrs, :deaths, -1)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
    end

    test "validates damage_done is non-negative" do
      attrs = Map.put(@valid_attrs, :damage_done, -100)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
    end

    test "validates healing_done is non-negative" do
      attrs = Map.put(@valid_attrs, :healing_done, -100)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
    end

    test "validates duration_seconds is positive" do
      attrs = Map.put(@valid_attrs, :duration_seconds, 0)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?
    end

    test "validates mythic_level range" do
      attrs = Map.put(@valid_attrs, :mythic_level, 0)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :mythic_level, 31)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :mythic_level, 15)
      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      assert changeset.valid?
    end

    test "accepts optional stats fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          duration_seconds: 1800,
          deaths: 5,
          damage_done: 1_000_000,
          healing_done: 500_000,
          mythic_level: 10,
          timed: true
        })

      changeset = InstanceCompletion.changeset(%InstanceCompletion{}, attrs)
      assert changeset.valid?
    end
  end

  describe "new_completion/5" do
    test "creates a completion for current time" do
      changeset = InstanceCompletion.new_completion(1, 100, "dungeon", "veteran")
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :character_id) == 1
      assert Ecto.Changeset.get_field(changeset, :instance_definition_id) == 100
      assert Ecto.Changeset.get_field(changeset, :instance_type) == "dungeon"
      assert Ecto.Changeset.get_field(changeset, :difficulty) == "veteran"
      assert Ecto.Changeset.get_field(changeset, :completed_at) != nil
    end

    test "accepts stats map" do
      stats = %{deaths: 3, damage_done: 500_000}
      changeset = InstanceCompletion.new_completion(1, 100, "raid", "veteran", stats)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :deaths) == 3
      assert Ecto.Changeset.get_field(changeset, :damage_done) == 500_000
    end
  end

  describe "mythic_plus?/1" do
    test "returns true for mythic_plus difficulty" do
      completion = %InstanceCompletion{difficulty: "mythic_plus"}
      assert InstanceCompletion.mythic_plus?(completion)
    end

    test "returns false for other difficulties" do
      for diff <- ~w(normal veteran challenge) do
        completion = %InstanceCompletion{difficulty: diff}
        refute InstanceCompletion.mythic_plus?(completion)
      end
    end
  end

  describe "timed_run?/1" do
    test "returns true when timed is true" do
      completion = %InstanceCompletion{timed: true}
      assert InstanceCompletion.timed_run?(completion)
    end

    test "returns false when timed is false" do
      completion = %InstanceCompletion{timed: false}
      refute InstanceCompletion.timed_run?(completion)
    end

    test "returns false when timed is nil" do
      completion = %InstanceCompletion{timed: nil}
      refute InstanceCompletion.timed_run?(completion)
    end
  end
end
