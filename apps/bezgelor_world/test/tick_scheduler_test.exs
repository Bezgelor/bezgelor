defmodule BezgelorWorld.TickSchedulerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.TickScheduler

  setup do
    # Start with a fast tick rate for testing
    {:ok, pid} = start_supervised({TickScheduler, tick_interval: 50})
    %{scheduler: pid}
  end

  describe "tick scheduling" do
    test "fires ticks at regular intervals" do
      # Register to receive tick notifications
      TickScheduler.register_listener(self())

      # Wait for 3 ticks
      assert_receive {:tick, tick_num}, 200
      assert tick_num >= 1

      assert_receive {:tick, _}, 200
      assert_receive {:tick, _}, 200
    end

    test "tick number increments" do
      TickScheduler.register_listener(self())

      assert_receive {:tick, tick1}, 200
      assert_receive {:tick, tick2}, 200

      assert tick2 > tick1
    end
  end

  describe "listener management" do
    test "can unregister listener" do
      TickScheduler.register_listener(self())
      assert_receive {:tick, _}, 200

      TickScheduler.unregister_listener(self())

      # Should not receive any more ticks
      refute_receive {:tick, _}, 150
    end
  end
end
