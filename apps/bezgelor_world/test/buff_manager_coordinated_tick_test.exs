defmodule BezgelorWorld.BuffManagerCoordinatedTickTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.BuffManager
  alias BezgelorCore.BuffDebuff

  # Note: TickScheduler and BuffManager are started by the application supervisor.
  # These tests verify coordinated ticking behavior with the global instances.

  setup do
    # Clear any existing test entities
    BuffManager.clear_entity(12345)
    BuffManager.clear_entity(67890)
    :ok
  end

  describe "coordinated periodic ticks" do
    test "multiple periodic buffs tick together on scheduler tick" do
      player1_guid = 12345
      player2_guid = 67890

      # Apply periodic buffs to two players
      buff1 =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 1,
          buff_type: :periodic,
          amount: 10,
          duration: 5000,
          tick_interval: 1000,
          is_debuff: true
        })

      buff2 =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 2,
          buff_type: :periodic,
          amount: 20,
          duration: 5000,
          tick_interval: 1000,
          is_debuff: false
        })

      {:ok, _} = BuffManager.apply_buff(player1_guid, buff1, 99999)
      {:ok, _} = BuffManager.apply_buff(player2_guid, buff2, 99999)

      # Wait for at least one tick cycle
      Process.sleep(1500)

      # Both buffs should still be active
      assert BuffManager.has_buff?(player1_guid, 1)
      assert BuffManager.has_buff?(player2_guid, 2)
    end

    test "periodic effects are processed on TickScheduler ticks" do
      entity_guid = 12345

      # Apply a periodic buff
      buff =
        BuffDebuff.new(%{
          id: 100,
          spell_id: 100,
          buff_type: :periodic,
          amount: 50,
          duration: 3000,
          tick_interval: 1000,
          is_debuff: false
        })

      {:ok, _} = BuffManager.apply_buff(entity_guid, buff, 99999)

      # Buff should be active
      assert BuffManager.has_buff?(entity_guid, 100)

      # Wait for ticks to process (coordinated with global TickScheduler)
      Process.sleep(2500)

      # Buff should still be active (5s duration)
      assert BuffManager.has_buff?(entity_guid, 100)
    end
  end
end
