defmodule BezgelorDb.Schema.GroupFinderGroupTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.GroupFinderGroup

  @valid_attrs %{
    group_guid: <<1, 2, 3, 4, 5, 6, 7, 8>>,
    instance_definition_id: 100,
    difficulty: "veteran",
    member_ids: [1, 2, 3, 4, 5],
    roles: %{"tank" => [1], "healer" => [2], "dps" => [3, 4, 5]}
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without group_guid" do
      attrs = Map.delete(@valid_attrs, :group_guid)
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).group_guid
    end

    test "invalid without instance_definition_id" do
      attrs = Map.delete(@valid_attrs, :instance_definition_id)
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).instance_definition_id
    end

    test "invalid without difficulty" do
      attrs = Map.delete(@valid_attrs, :difficulty)
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).difficulty
    end

    test "invalid without member_ids" do
      attrs = Map.delete(@valid_attrs, :member_ids)
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).member_ids
    end

    test "invalid without roles" do
      attrs = Map.delete(@valid_attrs, :roles)
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).roles
    end

    test "invalid difficulty" do
      attrs = Map.put(@valid_attrs, :difficulty, "invalid")
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).difficulty
    end

    test "invalid status" do
      attrs = Map.put(@valid_attrs, :status, "invalid")
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "accepts all valid difficulties" do
      for diff <- ~w(normal veteran challenge mythic_plus) do
        attrs = Map.put(@valid_attrs, :difficulty, diff)
        changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
        assert changeset.valid?, "Expected #{diff} to be valid"
      end
    end

    test "accepts all valid statuses" do
      for status <- ~w(forming ready entering active disbanded) do
        attrs = Map.put(@valid_attrs, :status, status)
        changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, attrs)
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "defaults status to forming" do
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == "forming"
    end

    test "defaults ready_check to empty map" do
      changeset = GroupFinderGroup.changeset(%GroupFinderGroup{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :ready_check) == %{}
    end
  end

  describe "set_ready/3" do
    test "sets a player's ready status to true" do
      group = %GroupFinderGroup{ready_check: %{}}
      changeset = GroupFinderGroup.set_ready(group, 1, true)
      ready_check = Ecto.Changeset.get_change(changeset, :ready_check)
      assert ready_check["1"] == true
    end

    test "sets a player's ready status to false" do
      group = %GroupFinderGroup{ready_check: %{"1" => true}}
      changeset = GroupFinderGroup.set_ready(group, 1, false)
      ready_check = Ecto.Changeset.get_change(changeset, :ready_check)
      assert ready_check["1"] == false
    end

    test "preserves other players' ready status" do
      group = %GroupFinderGroup{ready_check: %{"2" => true}}
      changeset = GroupFinderGroup.set_ready(group, 1, true)
      ready_check = Ecto.Changeset.get_change(changeset, :ready_check)
      assert ready_check["1"] == true
      assert ready_check["2"] == true
    end
  end

  describe "all_ready?/1" do
    test "returns true when all members are ready" do
      group = %GroupFinderGroup{
        member_ids: [1, 2, 3],
        ready_check: %{"1" => true, "2" => true, "3" => true}
      }

      assert GroupFinderGroup.all_ready?(group)
    end

    test "returns false when some members are not ready" do
      group = %GroupFinderGroup{
        member_ids: [1, 2, 3],
        ready_check: %{"1" => true, "2" => false, "3" => true}
      }

      refute GroupFinderGroup.all_ready?(group)
    end

    test "returns false when some members have no ready status" do
      group = %GroupFinderGroup{
        member_ids: [1, 2, 3],
        ready_check: %{"1" => true, "2" => true}
      }

      refute GroupFinderGroup.all_ready?(group)
    end

    test "returns false when ready_check is empty" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3], ready_check: %{}}
      refute GroupFinderGroup.all_ready?(group)
    end
  end

  describe "ready_count/1" do
    test "returns count of ready members" do
      group = %GroupFinderGroup{
        member_ids: [1, 2, 3, 4, 5],
        ready_check: %{"1" => true, "2" => true, "3" => false}
      }

      assert GroupFinderGroup.ready_count(group) == 2
    end

    test "returns 0 when no members are ready" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3], ready_check: %{}}
      assert GroupFinderGroup.ready_count(group) == 0
    end
  end

  describe "set_status/2" do
    test "changes group status" do
      group = %GroupFinderGroup{status: "forming"}
      changeset = GroupFinderGroup.set_status(group, "ready")
      assert Ecto.Changeset.get_change(changeset, :status) == "ready"
    end
  end

  describe "member?/2" do
    test "returns true when character is a member" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3, 4, 5]}
      assert GroupFinderGroup.member?(group, 3)
    end

    test "returns false when character is not a member" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3, 4, 5]}
      refute GroupFinderGroup.member?(group, 10)
    end
  end

  describe "role accessors" do
    test "tanks/1 returns tank IDs" do
      group = %GroupFinderGroup{roles: %{"tank" => [1], "healer" => [2], "dps" => [3, 4, 5]}}
      assert GroupFinderGroup.tanks(group) == [1]
    end

    test "healers/1 returns healer IDs" do
      group = %GroupFinderGroup{roles: %{"tank" => [1], "healer" => [2], "dps" => [3, 4, 5]}}
      assert GroupFinderGroup.healers(group) == [2]
    end

    test "dps/1 returns DPS IDs" do
      group = %GroupFinderGroup{roles: %{"tank" => [1], "healer" => [2], "dps" => [3, 4, 5]}}
      assert GroupFinderGroup.dps(group) == [3, 4, 5]
    end

    test "returns empty list for missing role" do
      group = %GroupFinderGroup{roles: %{}}
      assert GroupFinderGroup.tanks(group) == []
      assert GroupFinderGroup.healers(group) == []
      assert GroupFinderGroup.dps(group) == []
    end
  end

  describe "member_count/1" do
    test "returns number of members" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3, 4, 5]}
      assert GroupFinderGroup.member_count(group) == 5
    end

    test "returns 0 for empty group" do
      group = %GroupFinderGroup{member_ids: []}
      assert GroupFinderGroup.member_count(group) == 0
    end
  end

  describe "full?/2" do
    test "returns true when at max size" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3, 4, 5]}
      assert GroupFinderGroup.full?(group)
    end

    test "returns false when below max size" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3]}
      refute GroupFinderGroup.full?(group)
    end

    test "uses custom max size" do
      group = %GroupFinderGroup{member_ids: [1, 2, 3]}
      assert GroupFinderGroup.full?(group, 3)
      refute GroupFinderGroup.full?(group, 5)
    end
  end

  describe "statuses/0" do
    test "returns list of valid statuses" do
      statuses = GroupFinderGroup.statuses()
      assert "forming" in statuses
      assert "ready" in statuses
      assert "entering" in statuses
      assert "active" in statuses
      assert "disbanded" in statuses
    end
  end
end
