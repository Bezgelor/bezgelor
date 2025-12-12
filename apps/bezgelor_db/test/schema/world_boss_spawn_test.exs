defmodule BezgelorDb.Schema.WorldBossSpawnTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.WorldBossSpawn

  @valid_attrs %{
    boss_id: 5001,
    zone_id: 100,
    state: :waiting
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with minimal required fields" do
      attrs = %{boss_id: 5001, zone_id: 100}
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, attrs)
      assert changeset.valid?
    end

    test "invalid without boss_id" do
      attrs = Map.delete(@valid_attrs, :boss_id)
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).boss_id
    end

    test "invalid without zone_id" do
      attrs = Map.delete(@valid_attrs, :zone_id)
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).zone_id
    end

    test "accepts all valid states" do
      for state <- WorldBossSpawn.valid_states() do
        attrs = Map.put(@valid_attrs, :state, state)
        changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, attrs)
        assert changeset.valid?, "Expected state #{state} to be valid"
      end
    end

    test "defaults state to waiting" do
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, %{boss_id: 1, zone_id: 1})
      assert Ecto.Changeset.get_field(changeset, :state) == :waiting
    end

    test "accepts spawn window timestamps" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      window_start = DateTime.add(now, 3600, :second)
      window_end = DateTime.add(now, 7200, :second)

      attrs = Map.merge(@valid_attrs, %{
        spawn_window_start: window_start,
        spawn_window_end: window_end
      })
      changeset = WorldBossSpawn.changeset(%WorldBossSpawn{}, attrs)
      assert changeset.valid?
    end
  end

  describe "set_window_changeset/3" do
    test "sets spawn window and state to waiting" do
      spawn = %WorldBossSpawn{state: :killed, spawned_at: DateTime.utc_now()}
      window_start = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      window_end = DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second)

      changeset = WorldBossSpawn.set_window_changeset(spawn, window_start, window_end)

      assert Ecto.Changeset.get_change(changeset, :state) == :waiting
      assert Ecto.Changeset.get_change(changeset, :spawn_window_start) == window_start
      assert Ecto.Changeset.get_change(changeset, :spawn_window_end) == window_end
      assert Ecto.Changeset.get_change(changeset, :spawned_at) == nil
      assert Ecto.Changeset.get_change(changeset, :killed_at) == nil
    end
  end

  describe "spawn_changeset/1" do
    test "sets state to spawned and spawned_at timestamp" do
      spawn = %WorldBossSpawn{state: :waiting}

      changeset = WorldBossSpawn.spawn_changeset(spawn)

      assert Ecto.Changeset.get_change(changeset, :state) == :spawned
      assert Ecto.Changeset.get_change(changeset, :spawned_at) != nil
    end
  end

  describe "engage_changeset/1" do
    test "sets state to engaged" do
      spawn = %WorldBossSpawn{state: :spawned}

      changeset = WorldBossSpawn.engage_changeset(spawn)

      assert Ecto.Changeset.get_change(changeset, :state) == :engaged
    end
  end

  describe "kill_changeset/2" do
    test "sets state to killed with timestamps" do
      spawn = %WorldBossSpawn{state: :engaged}
      next_spawn = DateTime.add(DateTime.utc_now(), 86400, :second) |> DateTime.truncate(:second)

      changeset = WorldBossSpawn.kill_changeset(spawn, next_spawn)

      assert Ecto.Changeset.get_change(changeset, :state) == :killed
      assert Ecto.Changeset.get_change(changeset, :killed_at) != nil
      assert Ecto.Changeset.get_change(changeset, :next_spawn_after) == next_spawn
    end
  end

  describe "reset_changeset/1" do
    test "resets all fields to waiting state" do
      spawn = %WorldBossSpawn{
        state: :killed,
        spawn_window_start: DateTime.utc_now(),
        spawn_window_end: DateTime.utc_now(),
        spawned_at: DateTime.utc_now(),
        killed_at: DateTime.utc_now()
      }

      changeset = WorldBossSpawn.reset_changeset(spawn)

      assert Ecto.Changeset.get_change(changeset, :state) == :waiting
      assert Ecto.Changeset.get_change(changeset, :spawn_window_start) == nil
      assert Ecto.Changeset.get_change(changeset, :spawn_window_end) == nil
      assert Ecto.Changeset.get_change(changeset, :spawned_at) == nil
      assert Ecto.Changeset.get_change(changeset, :killed_at) == nil
    end
  end

  describe "valid_states/0" do
    test "returns list of valid states" do
      states = WorldBossSpawn.valid_states()
      assert :waiting in states
      assert :spawned in states
      assert :engaged in states
      assert :killed in states
    end
  end

  describe "state transitions" do
    test "waiting -> spawned -> engaged -> killed flow" do
      spawn = %WorldBossSpawn{state: :waiting}

      # Spawn the boss
      spawn_changeset = WorldBossSpawn.spawn_changeset(spawn)
      spawned_state = Ecto.Changeset.get_change(spawn_changeset, :state)
      assert spawned_state == :spawned

      # Engage the boss
      spawned_spawn = %WorldBossSpawn{state: :spawned}
      engage_changeset = WorldBossSpawn.engage_changeset(spawned_spawn)
      engaged_state = Ecto.Changeset.get_change(engage_changeset, :state)
      assert engaged_state == :engaged

      # Kill the boss
      engaged_spawn = %WorldBossSpawn{state: :engaged}
      next_spawn = DateTime.add(DateTime.utc_now(), 86400, :second) |> DateTime.truncate(:second)
      kill_changeset = WorldBossSpawn.kill_changeset(engaged_spawn, next_spawn)
      killed_state = Ecto.Changeset.get_change(kill_changeset, :state)
      assert killed_state == :killed
    end
  end
end
