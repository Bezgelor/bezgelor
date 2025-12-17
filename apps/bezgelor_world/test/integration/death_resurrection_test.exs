defmodule BezgelorWorld.Integration.DeathResurrectionTest do
  @moduledoc """
  Integration tests for player death and resurrection flow.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.DeathManager
  alias BezgelorCore.Death

  @moduletag :integration

  setup do
    # Start a fresh DeathManager for each test
    case GenServer.whereis(DeathManager) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
    end

    {:ok, _pid} = DeathManager.start_link([])
    :ok
  end

  describe "player death flow" do
    test "player enters death state when killed" do
      player_guid = 0x1000000000000001
      zone_id = 426
      position = {100.0, 50.0, 200.0}
      killer_guid = 0x0400000000000002

      # Player starts alive
      assert DeathManager.is_dead?(player_guid) == false

      # Player dies
      :ok = DeathManager.player_died(player_guid, zone_id, position, killer_guid)

      # Player is now dead
      assert DeathManager.is_dead?(player_guid) == true

      # Death info is available
      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.zone_id == zone_id
      assert info.position == position
      assert info.killer_guid == killer_guid
    end

    test "environmental death (no killer)" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {500.0, 100.0, 300.0}

      # Fall damage death
      :ok = DeathManager.player_died(player_guid, zone_id, position, nil)

      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.killer_guid == nil
    end
  end

  describe "resurrection spell flow" do
    test "player can accept resurrection offer" do
      player_guid = 0x1000000000000001
      caster_guid = 0x1000000000000002
      death_position = {100.0, 50.0, 200.0}
      health_percent = 35.0

      # Player dies
      DeathManager.player_died(player_guid, 100, death_position, nil)
      assert DeathManager.is_dead?(player_guid) == true

      # Another player offers resurrection
      :ok = DeathManager.offer_resurrection(player_guid, caster_guid, 12345, health_percent)

      # Player accepts
      {:ok, result} = DeathManager.accept_resurrection(player_guid)

      # Verify result
      assert result.position == death_position
      assert result.health_percent == health_percent
      assert result.resurrect_type == :spell

      # Player is alive again
      assert DeathManager.is_dead?(player_guid) == false
    end

    test "player can decline resurrection offer" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.offer_resurrection(player_guid, 0x1000000000000002, 12345, 35.0)

      # Decline the offer
      :ok = DeathManager.decline_resurrection(player_guid)

      # Player is still dead, but no offer pending
      assert DeathManager.is_dead?(player_guid) == true
      assert {:error, :no_offer} = DeathManager.accept_resurrection(player_guid)
    end
  end

  describe "bindpoint respawn flow" do
    test "player respawns at bindpoint with reduced health" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {100.0, 50.0, 200.0}

      # Player dies
      DeathManager.player_died(player_guid, zone_id, position, nil)
      assert DeathManager.is_dead?(player_guid) == true

      # Player chooses to respawn at bindpoint
      {:ok, result} = DeathManager.respawn_at_bindpoint(player_guid)

      # Verify respawn result
      assert is_integer(result.zone_id)
      assert is_tuple(result.position)
      assert result.health_percent > 0.0
      assert result.resurrect_type == :bindpoint

      # Player is alive again
      assert DeathManager.is_dead?(player_guid) == false
    end
  end

  describe "death penalty calculations" do
    test "durability loss scales with level" do
      # Low level: no durability loss
      assert Death.durability_loss(5) == 0.0
      assert Death.durability_loss(9) == 0.0

      # Mid level: 5% loss
      assert Death.durability_loss(10) == 5.0
      assert Death.durability_loss(29) == 5.0

      # Higher level: 10% loss
      assert Death.durability_loss(30) == 10.0
      assert Death.durability_loss(49) == 10.0

      # Max level: 15% loss
      assert Death.durability_loss(50) == 15.0
      assert Death.durability_loss(60) == 15.0
    end

    test "respawn health scales with level" do
      # Low level: 50% health
      assert Death.respawn_health_percent(1) == 50.0
      assert Death.respawn_health_percent(19) == 50.0

      # Mid level: 35% health
      assert Death.respawn_health_percent(20) == 35.0
      assert Death.respawn_health_percent(39) == 35.0

      # High level: 25% health
      assert Death.respawn_health_percent(40) == 25.0
      assert Death.respawn_health_percent(50) == 25.0
    end
  end

  describe "resurrection sickness" do
    test "no sickness for fewer than 3 deaths" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      {should_apply, count} = DeathManager.should_apply_resurrection_sickness?(player_guid)
      assert should_apply == false
      assert count == 2
    end

    test "sickness applies after 3+ deaths in window" do
      player_guid = 0x1000000000000001

      # Die 3 times
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      {should_apply, count} = DeathManager.should_apply_resurrection_sickness?(player_guid)
      assert should_apply == true
      assert count == 3
    end

    test "death count tracks multiple deaths" do
      player_guid = 0x1000000000000001

      assert DeathManager.get_death_count(player_guid) == 0

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.get_death_count(player_guid) == 1

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.get_death_count(player_guid) == 2

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.get_death_count(player_guid) == 3
    end
  end

  describe "resurrection health calculation" do
    test "calculates resurrection health from percentage" do
      assert Death.resurrection_health(10000, 35.0) == 3500
      assert Death.resurrection_health(10000, 50.0) == 5000
      assert Death.resurrection_health(10000, 100.0) == 10000
      assert Death.resurrection_health(10000, 0.0) == 0
    end

    test "clamps percentage to valid range" do
      assert Death.resurrection_health(10000, 150.0) == 10000
      assert Death.resurrection_health(10000, -50.0) == 0
    end
  end
end
