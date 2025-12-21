defmodule BezgelorCore.SpellEffectTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.SpellEffect

  describe "calculate_damage/4" do
    test "calculates base damage without scaling" do
      effect = %SpellEffect{
        type: :damage,
        amount: 100,
        scaling: 0.0,
        scaling_stat: nil,
        school: :magic
      }

      caster_stats = %{power: 100, crit_chance: 0}
      target_stats = %{}

      {damage, is_crit} = SpellEffect.calculate_damage(effect, caster_stats, target_stats)

      assert damage == 100
      refute is_crit
    end

    test "applies stat scaling" do
      effect = %SpellEffect{
        type: :damage,
        amount: 100,
        scaling: 0.5,
        scaling_stat: :power,
        school: :magic
      }

      caster_stats = %{power: 200, crit_chance: 0}
      target_stats = %{}

      {damage, _is_crit} = SpellEffect.calculate_damage(effect, caster_stats, target_stats)

      # 100 base + (200 * 0.5) = 200
      assert damage == 200
    end

    test "applies armor mitigation" do
      effect = %SpellEffect{
        type: :damage,
        amount: 100,
        scaling: 0.0,
        scaling_stat: nil,
        school: :physical
      }

      caster_stats = %{crit_chance: 0}
      target_stats = %{armor: 0.25}

      {damage, _is_crit} = SpellEffect.calculate_damage(effect, caster_stats, target_stats)

      # 100 * (1 - 0.25) = 75
      assert damage == 75
    end

    test "force critical hit" do
      effect = %SpellEffect{
        type: :damage,
        amount: 100,
        scaling: 0.0,
        scaling_stat: nil,
        school: :magic
      }

      caster_stats = %{crit_chance: 0}

      {damage, is_crit} =
        SpellEffect.calculate_damage(effect, caster_stats, %{}, force_crit: true)

      # 100 * 1.5 = 150
      assert damage == 150
      assert is_crit
    end

    test "damage cannot be negative" do
      effect = %SpellEffect{
        type: :damage,
        amount: 0,
        scaling: 0.0,
        scaling_stat: nil,
        school: :magic
      }

      {damage, _is_crit} = SpellEffect.calculate_damage(effect, %{crit_chance: 0}, %{})

      assert damage == 0
    end
  end

  describe "calculate_healing/3" do
    test "calculates base healing" do
      effect = %SpellEffect{
        type: :heal,
        amount: 150,
        scaling: 0.0,
        scaling_stat: nil
      }

      caster_stats = %{support: 100, crit_chance: 0}

      {healing, is_crit} = SpellEffect.calculate_healing(effect, caster_stats)

      assert healing == 150
      refute is_crit
    end

    test "applies support scaling" do
      effect = %SpellEffect{
        type: :heal,
        amount: 100,
        scaling: 0.8,
        scaling_stat: :support
      }

      caster_stats = %{support: 100, crit_chance: 0}

      {healing, _is_crit} = SpellEffect.calculate_healing(effect, caster_stats)

      # 100 base + (100 * 0.8) = 180
      assert healing == 180
    end

    test "critical heal" do
      effect = %SpellEffect{
        type: :heal,
        amount: 100,
        scaling: 0.0,
        scaling_stat: nil
      }

      caster_stats = %{crit_chance: 0}

      {healing, is_crit} = SpellEffect.calculate_healing(effect, caster_stats, force_crit: true)

      assert healing == 150
      assert is_crit
    end
  end

  describe "calculate/4" do
    test "dispatches to damage for :damage type" do
      effect = %SpellEffect{type: :damage, amount: 100, scaling: 0.0}

      {value, _} = SpellEffect.calculate(effect, %{crit_chance: 0}, %{})

      assert value == 100
    end

    test "dispatches to healing for :heal type" do
      effect = %SpellEffect{type: :heal, amount: 100, scaling: 0.0}

      {value, _} = SpellEffect.calculate(effect, %{crit_chance: 0})

      assert value == 100
    end

    test "returns base amount for buff type" do
      effect = %SpellEffect{type: :buff, amount: 50}

      {value, is_crit} = SpellEffect.calculate(effect, %{}, %{})

      assert value == 50
      refute is_crit
    end
  end

  describe "tick_count/1" do
    test "calculates number of ticks for DoT" do
      effect = %SpellEffect{
        type: :dot,
        duration: 10_000,
        tick_interval: 1000
      }

      assert 10 == SpellEffect.tick_count(effect)
    end

    test "returns 0 for no duration" do
      effect = %SpellEffect{type: :damage, duration: 0, tick_interval: 1000}

      assert 0 == SpellEffect.tick_count(effect)
    end

    test "returns 0 for no tick interval" do
      effect = %SpellEffect{type: :damage, duration: 10_000, tick_interval: 0}

      assert 0 == SpellEffect.tick_count(effect)
    end
  end

  describe "over_time?/1" do
    test "returns true for DoT" do
      effect = %SpellEffect{type: :dot}
      assert SpellEffect.over_time?(effect)
    end

    test "returns true for HoT" do
      effect = %SpellEffect{type: :hot}
      assert SpellEffect.over_time?(effect)
    end

    test "returns false for instant effects" do
      refute SpellEffect.over_time?(%SpellEffect{type: :damage})
      refute SpellEffect.over_time?(%SpellEffect{type: :heal})
    end
  end

  describe "type conversion" do
    test "type_to_int/1 converts correctly" do
      assert 0 == SpellEffect.type_to_int(:damage)
      assert 1 == SpellEffect.type_to_int(:heal)
      assert 2 == SpellEffect.type_to_int(:buff)
      assert 3 == SpellEffect.type_to_int(:debuff)
      assert 4 == SpellEffect.type_to_int(:dot)
      assert 5 == SpellEffect.type_to_int(:hot)
    end

    test "int_to_type/1 converts correctly" do
      assert :damage == SpellEffect.int_to_type(0)
      assert :heal == SpellEffect.int_to_type(1)
      assert :buff == SpellEffect.int_to_type(2)
      assert :debuff == SpellEffect.int_to_type(3)
      assert :dot == SpellEffect.int_to_type(4)
      assert :hot == SpellEffect.int_to_type(5)
    end
  end
end
