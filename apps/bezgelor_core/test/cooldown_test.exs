defmodule BezgelorCore.CooldownTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Cooldown

  describe "new/0" do
    test "creates empty cooldown state" do
      state = Cooldown.new()
      assert state == %{}
    end
  end

  describe "set/3" do
    test "sets cooldown for spell" do
      state = Cooldown.new()
      state = Cooldown.set(state, 1, 5000)

      refute Cooldown.ready?(state, 1)
    end

    test "ignores zero duration" do
      state = Cooldown.new()
      state = Cooldown.set(state, 1, 0)

      assert Cooldown.ready?(state, 1)
    end
  end

  describe "ready?/2" do
    test "returns true for spells not on cooldown" do
      state = Cooldown.new()
      assert Cooldown.ready?(state, 1)
    end

    test "returns false for spells on cooldown" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 10_000)

      refute Cooldown.ready?(state, 1)
    end

    test "returns true after cooldown expires" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 1)

      # Wait for cooldown to expire
      Process.sleep(5)

      assert Cooldown.ready?(state, 1)
    end
  end

  describe "remaining/2" do
    test "returns 0 for spells not on cooldown" do
      state = Cooldown.new()
      assert 0 == Cooldown.remaining(state, 1)
    end

    test "returns remaining time for active cooldowns" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 5000)

      remaining = Cooldown.remaining(state, 1)
      assert remaining > 0
      assert remaining <= 5000
    end

    test "returns 0 after cooldown expires" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 1)

      Process.sleep(5)

      assert 0 == Cooldown.remaining(state, 1)
    end
  end

  describe "gcd" do
    test "set_gcd/2 sets global cooldown" do
      state =
        Cooldown.new()
        |> Cooldown.set_gcd(1000)

      assert Cooldown.gcd_active?(state)
    end

    test "gcd_active?/1 returns false when no GCD" do
      state = Cooldown.new()
      refute Cooldown.gcd_active?(state)
    end

    test "gcd_remaining/1 returns remaining GCD time" do
      state =
        Cooldown.new()
        |> Cooldown.set_gcd(1000)

      remaining = Cooldown.gcd_remaining(state)
      assert remaining > 0
      assert remaining <= 1000
    end
  end

  describe "clear/2" do
    test "clears specific cooldown" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 5000)
        |> Cooldown.set(2, 5000)

      state = Cooldown.clear(state, 1)

      assert Cooldown.ready?(state, 1)
      refute Cooldown.ready?(state, 2)
    end
  end

  describe "clear_all/1" do
    test "clears all cooldowns" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 5000)
        |> Cooldown.set(2, 5000)
        |> Cooldown.set_gcd(1000)

      state = Cooldown.clear_all(state)

      assert Cooldown.ready?(state, 1)
      assert Cooldown.ready?(state, 2)
      refute Cooldown.gcd_active?(state)
    end
  end

  describe "can_cast?/3" do
    test "returns true when spell ready and no GCD" do
      state = Cooldown.new()
      assert Cooldown.can_cast?(state, 1, true)
    end

    test "returns false when spell on cooldown" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 5000)

      refute Cooldown.can_cast?(state, 1, true)
    end

    test "returns false when GCD active" do
      state =
        Cooldown.new()
        |> Cooldown.set_gcd(1000)

      refute Cooldown.can_cast?(state, 1, true)
    end

    test "ignores GCD when triggers_gcd is false" do
      state =
        Cooldown.new()
        |> Cooldown.set_gcd(1000)

      assert Cooldown.can_cast?(state, 1, false)
    end
  end

  describe "apply_cast/5" do
    test "applies spell and GCD cooldowns" do
      state = Cooldown.new()
      state = Cooldown.apply_cast(state, 1, 5000, true, 1000)

      refute Cooldown.ready?(state, 1)
      assert Cooldown.gcd_active?(state)
    end

    test "skips GCD when triggers_gcd is false" do
      state = Cooldown.new()
      state = Cooldown.apply_cast(state, 1, 5000, false, 1000)

      refute Cooldown.ready?(state, 1)
      refute Cooldown.gcd_active?(state)
    end
  end

  describe "active_cooldowns/1" do
    test "returns map of active cooldowns" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 5000)
        |> Cooldown.set(2, 10_000)

      active = Cooldown.active_cooldowns(state)

      assert Map.has_key?(active, 1)
      assert Map.has_key?(active, 2)
      assert active[1] > 0
      assert active[2] > 0
    end

    test "excludes expired cooldowns" do
      state =
        Cooldown.new()
        |> Cooldown.set(1, 1)

      Process.sleep(5)

      active = Cooldown.active_cooldowns(state)

      refute Map.has_key?(active, 1)
    end
  end
end
