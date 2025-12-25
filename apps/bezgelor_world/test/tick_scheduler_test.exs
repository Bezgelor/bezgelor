defmodule BezgelorWorld.TickSchedulerTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.TickScheduler

  # Note: TickScheduler is started by the application supervisor with 1000ms interval.
  # These tests use the globally running instance.

  setup do
    # Ensure we're unregistered before each test
    TickScheduler.unregister_listener(self())
    :ok
  end

  describe "tick scheduling" do
    test "fires ticks at regular intervals" do
      # Register to receive tick notifications
      TickScheduler.register_listener(self())

      # Wait for ticks (scheduler runs at 1000ms intervals)
      assert_receive {:tick, tick_num}, 2000
      assert tick_num >= 1

      assert_receive {:tick, _}, 2000
    end

    test "tick number increments" do
      TickScheduler.register_listener(self())

      assert_receive {:tick, tick1}, 2000
      assert_receive {:tick, tick2}, 2000

      assert tick2 > tick1
    end
  end

  describe "listener management" do
    test "can unregister listener" do
      TickScheduler.register_listener(self())
      assert_receive {:tick, _}, 2000

      TickScheduler.unregister_listener(self())

      # Should not receive any more ticks
      refute_receive {:tick, _}, 1500
    end
  end

  describe "API" do
    test "current_tick returns a number" do
      tick = TickScheduler.current_tick()
      assert is_integer(tick)
      assert tick >= 0
    end

    test "tick_interval returns 1000ms default" do
      interval = TickScheduler.tick_interval()
      assert interval == 1000
    end
  end
end
