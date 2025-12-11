defmodule BezgelorDb.Schema.TradeskillTalentTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.TradeskillTalent

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{character_id: 1, profession_id: 1, talent_id: 100}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      assert changeset.valid?
    end

    test "defaults points_spent to 1" do
      attrs = %{character_id: 1, profession_id: 1, talent_id: 100}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :points_spent) == 1
    end

    test "invalid without talent_id" do
      attrs = %{character_id: 1, profession_id: 1}
      changeset = TradeskillTalent.changeset(%TradeskillTalent{}, attrs)
      refute changeset.valid?
    end
  end

  describe "add_point_changeset/1" do
    test "increments points_spent" do
      talent = %TradeskillTalent{points_spent: 2}
      changeset = TradeskillTalent.add_point_changeset(talent)
      assert Ecto.Changeset.get_change(changeset, :points_spent) == 3
    end
  end
end
