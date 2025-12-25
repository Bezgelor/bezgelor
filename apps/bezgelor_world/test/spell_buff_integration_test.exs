defmodule BezgelorWorld.SpellBuffIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.{SpellManager, BuffManager}
  alias BezgelorCore.Spell

  setup do
    # Start managers if not already running (may be started by application)
    ensure_started(SpellManager)
    ensure_started(BuffManager)
    # Clear any existing state from previous tests
    BuffManager.clear_entity(12345)
    :ok
  end

  defp ensure_started(module) do
    case GenServer.whereis(module) do
      nil -> start_supervised!(module)
      _pid -> :already_running
    end
  end

  describe "casting Shield spell applies buff" do
    test "Shield spell (id 4) exists and has buff effect" do
      spell = Spell.get(4)

      assert spell != nil
      assert spell.name == "Shield"
      assert Spell.instant?(spell)

      # Verify spell has buff effect
      assert length(spell.effects) == 1
      effect = hd(spell.effects)
      assert effect.type == :buff
      assert effect.buff_type == :absorb
      assert effect.amount == 100
      assert effect.duration == 10_000
    end

    test "Shield spell returns buff effect when cast" do
      player_guid = 12345

      # Cast the Shield spell
      {:ok, :instant, result} = SpellManager.cast_spell(player_guid, 4, player_guid, nil, %{})

      # Verify effect was calculated
      assert length(result.effects) == 1
      effect = hd(result.effects)
      assert effect.type == :buff
    end

    test "BuffManager can apply buff from spell effect" do
      player_guid = 12345
      spell = Spell.get(4)
      effect = hd(spell.effects)

      # Create buff from spell effect (simulating what SpellHandler would do)
      buff =
        BezgelorCore.BuffDebuff.new(%{
          id: spell.id,
          spell_id: spell.id,
          buff_type: effect.buff_type,
          amount: effect.amount,
          duration: effect.duration
        })

      # Apply via BuffManager
      {:ok, _timer_ref} = BuffManager.apply_buff(player_guid, buff, player_guid)

      # Verify buff is active
      assert BuffManager.has_buff?(player_guid, spell.id)

      # Verify absorb shield is available
      {absorbed, remaining} = BuffManager.consume_absorb(player_guid, 50)
      assert absorbed == 50
      assert remaining == 0
    end
  end

  describe "complete spell-buff flow" do
    test "cast spell, apply buff, use buff, buff expires" do
      player_guid = 12345
      spell = Spell.get(4)
      effect = hd(spell.effects)

      # 1. Cast spell
      {:ok, :instant, _result} = SpellManager.cast_spell(player_guid, 4, player_guid, nil, %{})

      # 2. Apply buff (simulating what SpellHandler would do)
      buff =
        BezgelorCore.BuffDebuff.new(%{
          id: spell.id,
          spell_id: spell.id,
          buff_type: effect.buff_type,
          amount: effect.amount,
          # Short duration for test
          duration: 100
        })

      {:ok, _timer_ref} = BuffManager.apply_buff(player_guid, buff, player_guid)
      assert BuffManager.has_buff?(player_guid, spell.id)

      # 3. Use buff (absorb damage)
      {absorbed, remaining} = BuffManager.consume_absorb(player_guid, 30)
      assert absorbed == 30
      assert remaining == 0

      # Buff still has 70 absorb remaining
      buffs = BuffManager.get_entity_buffs(player_guid)
      assert length(buffs) == 1
      assert hd(buffs).buff.amount == 70

      # 4. Wait for expiration
      Process.sleep(150)
      refute BuffManager.has_buff?(player_guid, spell.id)
    end
  end
end
