defmodule BezgelorCore.BuffDebuffTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.BuffDebuff

  describe "new/1" do
    test "creates buff with required fields" do
      buff =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 4,
          buff_type: :absorb,
          amount: 100,
          duration: 10_000
        })

      assert buff.id == 1
      assert buff.spell_id == 4
      assert buff.buff_type == :absorb
      assert buff.amount == 100
      assert buff.duration == 10_000
      assert buff.is_debuff == false
    end

    test "creates debuff when is_debuff is true" do
      debuff =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          amount: -25,
          duration: 5_000,
          is_debuff: true,
          stat: :armor
        })

      assert debuff.is_debuff == true
      assert debuff.stat == :armor
    end
  end

  describe "buff?/1 and debuff?/1" do
    test "buff?/1 returns true for buffs" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :absorb, amount: 100, duration: 5000})

      assert BuffDebuff.buff?(buff)
      refute BuffDebuff.debuff?(buff)
    end

    test "debuff?/1 returns true for debuffs" do
      debuff =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 1,
          buff_type: :stat_modifier,
          amount: -10,
          duration: 5000,
          is_debuff: true
        })

      assert BuffDebuff.debuff?(debuff)
      refute BuffDebuff.buff?(debuff)
    end
  end

  describe "stat_modifier?/1" do
    test "returns true for stat_modifier buff_type" do
      buff =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 1,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 50,
          duration: 5000
        })

      assert BuffDebuff.stat_modifier?(buff)
    end

    test "returns false for non-stat buffs" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 1, buff_type: :absorb, amount: 100, duration: 5000})

      refute BuffDebuff.stat_modifier?(buff)
    end
  end

  describe "type_to_int/1 and int_to_type/1" do
    test "converts buff types to integers" do
      assert BuffDebuff.type_to_int(:absorb) == 0
      assert BuffDebuff.type_to_int(:stat_modifier) == 1
      assert BuffDebuff.type_to_int(:damage_boost) == 2
      assert BuffDebuff.type_to_int(:heal_boost) == 3
      assert BuffDebuff.type_to_int(:periodic) == 4
    end

    test "converts integers to buff types" do
      assert BuffDebuff.int_to_type(0) == :absorb
      assert BuffDebuff.int_to_type(1) == :stat_modifier
      assert BuffDebuff.int_to_type(2) == :damage_boost
      assert BuffDebuff.int_to_type(3) == :heal_boost
      assert BuffDebuff.int_to_type(4) == :periodic
    end
  end
end
