defmodule BezgelorWorld.BuffManagerPeriodicTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.BuffManager
  alias BezgelorCore.BuffDebuff

  setup do
    # Start BuffManager if not already running
    case GenServer.whereis(BuffManager) do
      nil -> start_supervised!(BuffManager)
      _pid -> :already_running
    end

    # Clear any existing state from previous tests
    BuffManager.clear_entity(12345)
    :ok
  end

  describe "periodic buff ticks" do
    test "periodic buff schedules and processes ticks" do
      player_guid = 12345

      # Create a periodic buff (HoT) with short intervals for testing
      buff =
        BuffDebuff.new(%{
          id: 5,
          spell_id: 5,
          buff_type: :periodic,
          amount: 25,
          duration: 250,
          tick_interval: 50,
          is_debuff: false
        })

      # Apply the buff
      {:ok, _timer_ref} = BuffManager.apply_buff(player_guid, buff, player_guid)
      assert BuffManager.has_buff?(player_guid, 5)

      # Wait for a few ticks to occur
      Process.sleep(180)

      # Buff should still be active
      assert BuffManager.has_buff?(player_guid, 5)

      # Wait for expiration
      Process.sleep(100)

      # Buff should be expired
      refute BuffManager.has_buff?(player_guid, 5)
    end

    test "periodic DoT (debuff) schedules ticks" do
      player_guid = 12345

      # Create a periodic debuff (DoT)
      buff =
        BuffDebuff.new(%{
          id: 10,
          spell_id: 10,
          buff_type: :periodic,
          amount: 15,
          duration: 150,
          tick_interval: 50,
          is_debuff: true
        })

      {:ok, _timer_ref} = BuffManager.apply_buff(player_guid, buff, 99999)
      assert BuffManager.has_buff?(player_guid, 10)

      # Wait for ticks and expiration
      Process.sleep(200)

      refute BuffManager.has_buff?(player_guid, 10)
    end

    test "removing periodic buff cancels tick timer" do
      player_guid = 12345

      buff =
        BuffDebuff.new(%{
          id: 5,
          spell_id: 5,
          buff_type: :periodic,
          amount: 25,
          duration: 1000,
          tick_interval: 50,
          is_debuff: false
        })

      {:ok, _timer_ref} = BuffManager.apply_buff(player_guid, buff, player_guid)
      assert BuffManager.has_buff?(player_guid, 5)

      # Remove the buff immediately
      :ok = BuffManager.remove_buff(player_guid, 5)
      refute BuffManager.has_buff?(player_guid, 5)

      # No ticks should occur after removal (buff was removed)
      Process.sleep(100)
      refute BuffManager.has_buff?(player_guid, 5)
    end
  end
end
