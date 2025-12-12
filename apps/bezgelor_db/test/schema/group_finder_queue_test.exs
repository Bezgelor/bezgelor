defmodule BezgelorDb.Schema.GroupFinderQueueTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.GroupFinderQueue

  @valid_attrs %{
    character_id: 1,
    account_id: 1,
    instance_type: "dungeon",
    instance_ids: [100, 101, 102],
    difficulty: "veteran",
    role: "tank",
    queued_at: DateTime.utc_now()
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without account_id" do
      attrs = Map.delete(@valid_attrs, :account_id)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "invalid without instance_type" do
      attrs = Map.delete(@valid_attrs, :instance_type)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_type
    end

    test "invalid without instance_ids" do
      attrs = Map.delete(@valid_attrs, :instance_ids)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_ids
    end

    test "invalid without difficulty" do
      attrs = Map.delete(@valid_attrs, :difficulty)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).difficulty
    end

    test "invalid without role" do
      attrs = Map.delete(@valid_attrs, :role)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "invalid without queued_at" do
      attrs = Map.delete(@valid_attrs, :queued_at)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).queued_at
    end

    test "invalid instance_type" do
      attrs = Map.put(@valid_attrs, :instance_type, "invalid")
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).instance_type
    end

    test "invalid difficulty" do
      attrs = Map.put(@valid_attrs, :difficulty, "invalid")
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).difficulty
    end

    test "invalid role" do
      attrs = Map.put(@valid_attrs, :role, "invalid")
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "accepts all valid instance types" do
      for type <- ~w(dungeon adventure raid expedition) do
        attrs = Map.put(@valid_attrs, :instance_type, type)
        changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "accepts all valid difficulties" do
      for diff <- ~w(normal veteran challenge mythic_plus) do
        attrs = Map.put(@valid_attrs, :difficulty, diff)
        changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
        assert changeset.valid?, "Expected #{diff} to be valid"
      end
    end

    test "accepts all valid roles" do
      for role <- ~w(tank healer dps) do
        attrs = Map.put(@valid_attrs, :role, role)
        changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
        assert changeset.valid?, "Expected #{role} to be valid"
      end
    end

    test "validates instance_ids minimum length" do
      attrs = Map.put(@valid_attrs, :instance_ids, [])
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
    end

    test "validates gear_score is non-negative" do
      attrs = Map.put(@valid_attrs, :gear_score, -1)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
    end

    test "validates completion_rate range" do
      attrs = Map.put(@valid_attrs, :completion_rate, -0.1)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?

      attrs = Map.put(@valid_attrs, :completion_rate, 1.1)
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      refute changeset.valid?
    end

    test "defaults gear_score to 0" do
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :gear_score) == 0
    end

    test "defaults completion_rate to 1.0" do
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :completion_rate) == 1.0
    end

    test "defaults preferences to empty map" do
      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :preferences) == %{}
    end

    test "accepts optional fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          gear_score: 1500,
          completion_rate: 0.85,
          preferences: %{voice_chat: true},
          estimated_wait_seconds: 120
        })

      changeset = GroupFinderQueue.changeset(%GroupFinderQueue{}, attrs)
      assert changeset.valid?
    end
  end

  describe "update_estimate/2" do
    test "updates estimated wait time" do
      queue_entry = %GroupFinderQueue{estimated_wait_seconds: nil}
      changeset = GroupFinderQueue.update_estimate(queue_entry, 300)
      assert Ecto.Changeset.get_change(changeset, :estimated_wait_seconds) == 300
    end
  end

  describe "wait_time_seconds/1" do
    test "returns time spent in queue" do
      past = DateTime.add(DateTime.utc_now(), -120, :second)
      queue_entry = %GroupFinderQueue{queued_at: past}
      wait_time = GroupFinderQueue.wait_time_seconds(queue_entry)
      assert wait_time >= 120
      # Allow for some margin due to test execution time
      assert wait_time < 125
    end
  end

  describe "wants_instance?/2" do
    test "returns true when instance is in list" do
      queue_entry = %GroupFinderQueue{instance_ids: [100, 101, 102]}
      assert GroupFinderQueue.wants_instance?(queue_entry, 101)
    end

    test "returns false when instance is not in list" do
      queue_entry = %GroupFinderQueue{instance_ids: [100, 101, 102]}
      refute GroupFinderQueue.wants_instance?(queue_entry, 200)
    end
  end

  describe "role checks" do
    test "tank?/1 returns true for tank role" do
      assert GroupFinderQueue.tank?(%GroupFinderQueue{role: "tank"})
      refute GroupFinderQueue.tank?(%GroupFinderQueue{role: "healer"})
    end

    test "healer?/1 returns true for healer role" do
      assert GroupFinderQueue.healer?(%GroupFinderQueue{role: "healer"})
      refute GroupFinderQueue.healer?(%GroupFinderQueue{role: "dps"})
    end

    test "dps?/1 returns true for dps role" do
      assert GroupFinderQueue.dps?(%GroupFinderQueue{role: "dps"})
      refute GroupFinderQueue.dps?(%GroupFinderQueue{role: "tank"})
    end
  end

  describe "constants" do
    test "roles/0 returns list of valid roles" do
      roles = GroupFinderQueue.roles()
      assert "tank" in roles
      assert "healer" in roles
      assert "dps" in roles
    end

    test "instance_types/0 returns list of valid instance types" do
      types = GroupFinderQueue.instance_types()
      assert "dungeon" in types
      assert "adventure" in types
      assert "raid" in types
      assert "expedition" in types
    end

    test "difficulties/0 returns list of valid difficulties" do
      diffs = GroupFinderQueue.difficulties()
      assert "normal" in diffs
      assert "veteran" in diffs
      assert "challenge" in diffs
      assert "mythic_plus" in diffs
    end
  end
end
