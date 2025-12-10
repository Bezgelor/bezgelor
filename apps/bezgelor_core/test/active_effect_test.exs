defmodule BezgelorCore.ActiveEffectTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.ActiveEffect
  alias BezgelorCore.BuffDebuff

  describe "new/0" do
    test "creates empty state" do
      state = ActiveEffect.new()
      assert state == %{}
    end
  end

  describe "apply/4" do
    test "adds buff to state with expiration time" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert Map.has_key?(state, 1)
      assert state[1].buff == buff
      assert state[1].caster_guid == 12345
      assert state[1].expires_at == 1000 + 10_000
    end

    test "replaces existing buff with same id" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 150, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 2000)

      assert state[1].buff.amount == 150
      assert state[1].expires_at == 2000 + 10_000
    end
  end

  describe "remove/2" do
    test "removes buff from state" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      state = ActiveEffect.remove(state, 1)

      refute Map.has_key?(state, 1)
    end

    test "no-op if buff not present" do
      state = ActiveEffect.new()
      state = ActiveEffect.remove(state, 999)

      assert state == %{}
    end
  end

  describe "active?/3" do
    test "returns true if buff exists and not expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.active?(state, 1, 5000)
    end

    test "returns false if buff expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      refute ActiveEffect.active?(state, 1, 15_000)
    end

    test "returns false if buff not present" do
      state = ActiveEffect.new()
      refute ActiveEffect.active?(state, 999, 1000)
    end
  end

  describe "remaining/3" do
    test "returns remaining duration" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.remaining(state, 1, 5000) == 6000
    end

    test "returns 0 if expired" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.remaining(state, 1, 15_000) == 0
    end

    test "returns 0 if not present" do
      state = ActiveEffect.new()
      assert ActiveEffect.remaining(state, 999, 1000) == 0
    end
  end

  describe "cleanup/2" do
    test "removes expired effects" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: 50, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      state = ActiveEffect.cleanup(state, 10_000)

      refute Map.has_key?(state, 1)
      assert Map.has_key?(state, 2)
    end
  end

  describe "get_stat_modifier/3" do
    test "returns total modifier for a stat" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 25, duration: 10_000})
      buff3 = BuffDebuff.new(%{id: 3, spell_id: 6, buff_type: :stat_modifier, stat: :armor, amount: 10, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      state = ActiveEffect.apply(state, buff3, 12345, 1000)

      assert ActiveEffect.get_stat_modifier(state, :power, 5000) == 75
      assert ActiveEffect.get_stat_modifier(state, :armor, 5000) == 10
      assert ActiveEffect.get_stat_modifier(state, :tech, 5000) == 0
    end

    test "ignores expired modifiers" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :stat_modifier, stat: :power, amount: 50, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, stat: :power, amount: 25, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)

      assert ActiveEffect.get_stat_modifier(state, :power, 10_000) == 25
    end
  end

  describe "get_absorb_remaining/2" do
    test "returns total absorb amount" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)

      assert ActiveEffect.get_absorb_remaining(state, 5000) == 100
    end

    test "returns 0 if no absorb effects" do
      state = ActiveEffect.new()
      assert ActiveEffect.get_absorb_remaining(state, 1000) == 0
    end
  end

  describe "consume_absorb/3" do
    test "reduces absorb amount and returns remainder" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 30, 5000)

      assert absorbed == 30
      assert remaining_damage == 0
      assert state[1].buff.amount == 70
    end

    test "removes buff when fully consumed" do
      state = ActiveEffect.new()
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 50, duration: 10_000})

      state = ActiveEffect.apply(state, buff, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 100, 5000)

      assert absorbed == 50
      assert remaining_damage == 50
      refute Map.has_key?(state, 1)
    end

    test "consumes from multiple absorb buffs" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 30, duration: 10_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :absorb, amount: 50, duration: 10_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)
      {state, absorbed, remaining_damage} = ActiveEffect.consume_absorb(state, 60, 5000)

      assert absorbed == 60
      assert remaining_damage == 0
      # First buff consumed, second partially consumed
      refute Map.has_key?(state, 1)
      assert state[2].buff.amount == 20
    end
  end

  describe "list_active/2" do
    test "returns list of active effects" do
      state = ActiveEffect.new()
      buff1 = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 5_000})
      buff2 = BuffDebuff.new(%{id: 2, spell_id: 5, buff_type: :stat_modifier, amount: 50, duration: 15_000})

      state = ActiveEffect.apply(state, buff1, 12345, 1000)
      state = ActiveEffect.apply(state, buff2, 12345, 1000)

      active = ActiveEffect.list_active(state, 3000)
      assert length(active) == 2

      # After buff1 expires
      active = ActiveEffect.list_active(state, 10_000)
      assert length(active) == 1
      assert hd(active).buff.id == 2
    end
  end
end
