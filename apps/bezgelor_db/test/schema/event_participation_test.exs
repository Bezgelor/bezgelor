defmodule BezgelorDb.Schema.EventParticipationTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.EventParticipation

  @valid_attrs %{
    event_instance_id: 1,
    character_id: 100,
    contribution_score: 0,
    kills: 0,
    damage_dealt: 0,
    healing_done: 0,
    objectives_completed: [],
    reward_tier: :bronze,
    rewards_claimed: false
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = EventParticipation.changeset(%EventParticipation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with minimal required fields" do
      attrs = %{event_instance_id: 1, character_id: 100}
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      assert changeset.valid?
    end

    test "invalid without event_instance_id" do
      attrs = Map.delete(@valid_attrs, :event_instance_id)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_instance_id
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid with negative contribution_score" do
      attrs = Map.put(@valid_attrs, :contribution_score, -1)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative kills" do
      attrs = Map.put(@valid_attrs, :kills, -1)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative damage_dealt" do
      attrs = Map.put(@valid_attrs, :damage_dealt, -1)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative healing_done" do
      attrs = Map.put(@valid_attrs, :healing_done, -1)
      changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
      refute changeset.valid?
    end

    test "accepts all valid reward tiers" do
      for tier <- EventParticipation.valid_reward_tiers() do
        attrs = Map.put(@valid_attrs, :reward_tier, tier)
        changeset = EventParticipation.changeset(%EventParticipation{}, attrs)
        assert changeset.valid?, "Expected tier #{tier} to be valid"
      end
    end

    test "defaults contribution_score to 0" do
      changeset =
        EventParticipation.changeset(%EventParticipation{}, %{
          event_instance_id: 1,
          character_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :contribution_score) == 0
    end

    test "defaults kills to 0" do
      changeset =
        EventParticipation.changeset(%EventParticipation{}, %{
          event_instance_id: 1,
          character_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :kills) == 0
    end

    test "defaults rewards_claimed to false" do
      changeset =
        EventParticipation.changeset(%EventParticipation{}, %{
          event_instance_id: 1,
          character_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :rewards_claimed) == false
    end

    test "defaults objectives_completed to empty list" do
      changeset =
        EventParticipation.changeset(%EventParticipation{}, %{
          event_instance_id: 1,
          character_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :objectives_completed) == []
    end
  end

  describe "contribute_changeset/2" do
    test "increases contribution score" do
      participation = %EventParticipation{contribution_score: 50}

      changeset = EventParticipation.contribute_changeset(participation, 25)

      assert Ecto.Changeset.get_change(changeset, :contribution_score) == 75
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) != nil
    end
  end

  describe "kill_changeset/2" do
    test "increments kills and adds contribution" do
      participation = %EventParticipation{kills: 5, contribution_score: 100}

      changeset = EventParticipation.kill_changeset(participation, 10)

      assert Ecto.Changeset.get_change(changeset, :kills) == 6
      assert Ecto.Changeset.get_change(changeset, :contribution_score) == 110
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) != nil
    end
  end

  describe "damage_changeset/3" do
    test "adds damage and contribution" do
      participation = %EventParticipation{damage_dealt: 1000, contribution_score: 50}

      changeset = EventParticipation.damage_changeset(participation, 500, 5)

      assert Ecto.Changeset.get_change(changeset, :damage_dealt) == 1500
      assert Ecto.Changeset.get_change(changeset, :contribution_score) == 55
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) != nil
    end
  end

  describe "healing_changeset/3" do
    test "adds healing and contribution" do
      participation = %EventParticipation{healing_done: 500, contribution_score: 30}

      changeset = EventParticipation.healing_changeset(participation, 300, 3)

      assert Ecto.Changeset.get_change(changeset, :healing_done) == 800
      assert Ecto.Changeset.get_change(changeset, :contribution_score) == 33
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) != nil
    end
  end

  describe "complete_objective_changeset/3" do
    test "adds objective to list" do
      participation = %EventParticipation{objectives_completed: [], contribution_score: 0}

      changeset = EventParticipation.complete_objective_changeset(participation, 0, 50)

      assert 0 in Ecto.Changeset.get_change(changeset, :objectives_completed)
      assert Ecto.Changeset.get_change(changeset, :contribution_score) == 50
    end

    test "does not duplicate objectives" do
      participation = %EventParticipation{objectives_completed: [0, 1], contribution_score: 100}

      changeset = EventParticipation.complete_objective_changeset(participation, 0, 50)

      objectives = Ecto.Changeset.get_field(changeset, :objectives_completed)
      assert length(objectives) == 2
    end

    test "preserves existing objectives" do
      participation = %EventParticipation{objectives_completed: [0], contribution_score: 50}

      changeset = EventParticipation.complete_objective_changeset(participation, 1, 50)

      objectives = Ecto.Changeset.get_change(changeset, :objectives_completed)
      assert 0 in objectives
      assert 1 in objectives
    end
  end

  describe "set_tier_changeset/2" do
    test "sets reward tier" do
      participation = %EventParticipation{reward_tier: nil}

      changeset = EventParticipation.set_tier_changeset(participation, :gold)

      assert Ecto.Changeset.get_change(changeset, :reward_tier) == :gold
    end
  end

  describe "claim_rewards_changeset/1" do
    test "sets rewards_claimed to true" do
      participation = %EventParticipation{rewards_claimed: false}

      changeset = EventParticipation.claim_rewards_changeset(participation)

      assert Ecto.Changeset.get_change(changeset, :rewards_claimed) == true
    end
  end

  describe "valid_reward_tiers/0" do
    test "returns list of valid reward tiers" do
      tiers = EventParticipation.valid_reward_tiers()
      assert :gold in tiers
      assert :silver in tiers
      assert :bronze in tiers
      assert :participation in tiers
    end
  end
end
