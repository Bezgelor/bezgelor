defmodule BezgelorDb.Schema.CharacterTradeskillTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.CharacterTradeskill

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        character_id: 1,
        profession_id: 1,
        profession_type: :crafting
      }

      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = %{profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without profession_id" do
      attrs = %{character_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).profession_id
    end

    test "invalid without profession_type" do
      attrs = %{character_id: 1, profession_id: 1}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).profession_type
    end

    test "defaults skill_level to 0" do
      attrs = %{character_id: 1, profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :skill_level) == 0
    end

    test "defaults is_active to true" do
      attrs = %{character_id: 1, profession_id: 1, profession_type: :crafting}
      changeset = CharacterTradeskill.changeset(%CharacterTradeskill{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :is_active) == true
    end
  end

  describe "progress_changeset/2" do
    test "updates skill_level and skill_xp" do
      tradeskill = %CharacterTradeskill{skill_level: 5, skill_xp: 100}
      changeset = CharacterTradeskill.progress_changeset(tradeskill, %{skill_level: 6, skill_xp: 150})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :skill_level) == 6
      assert Ecto.Changeset.get_change(changeset, :skill_xp) == 150
    end

    test "validates skill_level is non-negative" do
      tradeskill = %CharacterTradeskill{}
      changeset = CharacterTradeskill.progress_changeset(tradeskill, %{skill_level: -1})
      refute changeset.valid?
    end
  end
end
