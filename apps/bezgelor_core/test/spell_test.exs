defmodule BezgelorCore.SpellTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Spell

  describe "get/1" do
    test "returns spell by ID" do
      spell = Spell.get(1)

      assert %Spell{} = spell
      assert spell.id == 1
      assert spell.name == "Fireball"
    end

    test "returns nil for unknown ID" do
      assert nil == Spell.get(999)
    end
  end

  describe "exists?/1" do
    test "returns true for known spells" do
      assert Spell.exists?(1)
      assert Spell.exists?(2)
      assert Spell.exists?(3)
    end

    test "returns false for unknown spells" do
      refute Spell.exists?(999)
    end
  end

  describe "instant?/1" do
    test "returns true for instant spells" do
      quick_strike = Spell.get(3)
      assert Spell.instant?(quick_strike)
    end

    test "returns false for cast-time spells" do
      fireball = Spell.get(1)
      refute Spell.instant?(fireball)
    end
  end

  describe "requires_target?/1" do
    test "returns true for enemy/ally targeted spells" do
      fireball = Spell.get(1)
      heal = Spell.get(2)

      assert Spell.requires_target?(fireball)
      assert Spell.requires_target?(heal)
    end

    test "returns false for self-targeted spells" do
      shield = Spell.get(4)
      regen = Spell.get(5)

      refute Spell.requires_target?(shield)
      refute Spell.requires_target?(regen)
    end
  end

  describe "targets_enemy?/1" do
    test "returns true for enemy spells" do
      fireball = Spell.get(1)
      assert Spell.targets_enemy?(fireball)
    end

    test "returns false for non-enemy spells" do
      heal = Spell.get(2)
      refute Spell.targets_enemy?(heal)
    end
  end

  describe "targets_ally?/1" do
    test "returns true for ally spells" do
      heal = Spell.get(2)
      assert Spell.targets_ally?(heal)
    end

    test "returns false for non-ally spells" do
      fireball = Spell.get(1)
      refute Spell.targets_ally?(fireball)
    end
  end

  describe "all_ids/0" do
    test "returns all spell IDs" do
      ids = Spell.all_ids()

      assert 1 in ids
      assert 2 in ids
      assert 3 in ids
      assert 4 in ids
      assert 5 in ids
    end
  end

  describe "global_cooldown/0" do
    test "returns GCD duration" do
      assert 1000 == Spell.global_cooldown()
    end
  end

  describe "spell properties" do
    test "fireball has correct properties" do
      spell = Spell.get(1)

      assert spell.cast_time == 2000
      assert spell.cooldown == 5000
      assert spell.range == 30.0
      assert spell.target_type == :enemy
      assert spell.gcd == true
    end

    test "quick strike is instant with melee range" do
      spell = Spell.get(3)

      assert spell.cast_time == 0
      assert spell.range == 5.0
    end

    test "shield is self-targeted" do
      spell = Spell.get(4)

      assert spell.target_type == :self
      assert spell.range == 0.0
    end
  end
end
