defmodule BezgelorCore.EntityBuffsTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Entity
  alias BezgelorCore.BuffDebuff
  alias BezgelorCore.ActiveEffect

  defp make_entity do
    %Entity{
      guid: 1,
      type: :player,
      name: "Test",
      health: 100,
      max_health: 100,
      active_effects: ActiveEffect.new()
    }
  end

  describe "apply_buff/4" do
    test "adds buff to entity" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      assert ActiveEffect.active?(entity.active_effects, 1, 5000)
    end
  end

  describe "remove_buff/2" do
    test "removes buff from entity" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.remove_buff(entity, 1)

      refute ActiveEffect.active?(entity.active_effects, 1, 5000)
    end
  end

  describe "has_buff?/3" do
    test "returns true if buff is active" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      assert Entity.has_buff?(entity, 1, 5000)
    end

    test "returns false if buff expired" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)

      refute Entity.has_buff?(entity, 1, 15_000)
    end
  end

  describe "get_modified_stat/4" do
    test "returns base stat with no modifiers" do
      entity = make_entity()
      base_stats = %{power: 100, armor: 0.1}

      assert Entity.get_modified_stat(entity, :power, base_stats, 1000) == 100
    end

    test "applies stat modifiers from buffs" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 4,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 50,
          duration: 10_000
        })

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      base_stats = %{power: 100}

      assert Entity.get_modified_stat(entity, :power, base_stats, 5000) == 150
    end

    test "applies debuff stat reductions" do
      entity = make_entity()

      debuff =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 4,
          buff_type: :stat_modifier,
          stat: :power,
          amount: -25,
          duration: 10_000,
          is_debuff: true
        })

      entity = Entity.apply_buff(entity, debuff, 12345, 1000)
      base_stats = %{power: 100}

      assert Entity.get_modified_stat(entity, :power, base_stats, 5000) == 75
    end
  end

  describe "apply_damage_with_absorb/3" do
    test "damage goes through with no absorb" do
      entity = make_entity()
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 30, 1000)

      assert entity.health == 70
      assert absorbed == 0
    end

    test "absorb reduces damage" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 50, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 30, 5000)

      assert entity.health == 100
      assert absorbed == 30
    end

    test "partial absorb when damage exceeds shield" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 20, duration: 10_000})

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      {entity, absorbed} = Entity.apply_damage_with_absorb(entity, 50, 5000)

      assert entity.health == 70
      assert absorbed == 20
    end
  end

  describe "cleanup_effects/2" do
    test "removes expired effects" do
      entity = make_entity()

      buff1 =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})

      buff2 =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          amount: 50,
          duration: 15_000
        })

      entity = Entity.apply_buff(entity, buff1, 12345, 1000)
      entity = Entity.apply_buff(entity, buff2, 12345, 1000)
      entity = Entity.cleanup_effects(entity, 10_000)

      refute Entity.has_buff?(entity, 1, 10_000)
      assert Entity.has_buff?(entity, 2, 10_000)
    end
  end

  describe "list_buffs/2" do
    test "returns list of active buffs" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      debuff =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          amount: -10,
          duration: 10_000,
          is_debuff: true
        })

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.apply_buff(entity, debuff, 12345, 1000)

      buffs = Entity.list_buffs(entity, 5000)
      assert length(buffs) == 1
      assert hd(buffs).buff.id == 1
    end
  end

  describe "list_debuffs/2" do
    test "returns list of active debuffs" do
      entity = make_entity()

      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      debuff =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          amount: -10,
          duration: 10_000,
          is_debuff: true
        })

      entity = Entity.apply_buff(entity, buff, 12345, 1000)
      entity = Entity.apply_buff(entity, debuff, 12345, 1000)

      debuffs = Entity.list_debuffs(entity, 5000)
      assert length(debuffs) == 1
      assert hd(debuffs).buff.id == 2
    end
  end
end
