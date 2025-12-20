defmodule BezgelorWorld.DeathManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.DeathManager

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

    {:ok, pid} = DeathManager.start_link([])
    %{pid: pid}
  end

  describe "player_died/4" do
    test "tracks player death state" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      killer_guid = 0x0400000000000002

      assert :ok = DeathManager.player_died(player_guid, zone_id, position, killer_guid)
      assert DeathManager.is_dead?(player_guid) == true
    end

    test "tracks death without killer (fall damage)" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {100.0, 50.0, 200.0}

      assert :ok = DeathManager.player_died(player_guid, zone_id, position, nil)
      assert DeathManager.is_dead?(player_guid) == true
    end
  end

  describe "is_dead?/1" do
    test "returns false for players who haven't died" do
      player_guid = 0x1000000000000001
      assert DeathManager.is_dead?(player_guid) == false
    end

    test "returns true for dead players" do
      player_guid = 0x1000000000000001
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.is_dead?(player_guid) == true
    end
  end

  describe "get_death_info/1" do
    test "returns death information for dead player" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      killer_guid = 0x0400000000000002

      DeathManager.player_died(player_guid, zone_id, position, killer_guid)

      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.zone_id == zone_id
      assert info.position == position
      assert info.killer_guid == killer_guid
      assert is_integer(info.died_at)
    end

    test "returns error for living player" do
      player_guid = 0x1000000000000001
      assert {:error, :not_dead} = DeathManager.get_death_info(player_guid)
    end
  end

  describe "offer_resurrection/4" do
    test "offers resurrection to dead player" do
      player_guid = 0x1000000000000001
      caster_guid = 0x1000000000000002
      spell_id = 12345
      health_percent = 35.0

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      assert :ok =
               DeathManager.offer_resurrection(player_guid, caster_guid, spell_id, health_percent)
    end

    test "returns error for living player" do
      player_guid = 0x1000000000000001
      caster_guid = 0x1000000000000002

      assert {:error, :not_dead} =
               DeathManager.offer_resurrection(player_guid, caster_guid, 12345, 35.0)
    end
  end

  describe "accept_resurrection/1" do
    test "accepts pending resurrection offer" do
      player_guid = 0x1000000000000001
      caster_guid = 0x1000000000000002
      death_position = {100.0, 50.0, 200.0}
      health_percent = 35.0

      DeathManager.player_died(player_guid, 100, death_position, nil)
      DeathManager.offer_resurrection(player_guid, caster_guid, 12345, health_percent)

      {:ok, result} = DeathManager.accept_resurrection(player_guid)
      assert result.position == death_position
      assert result.health_percent == health_percent
      assert result.resurrect_type == :spell
    end

    test "player is no longer dead after accepting resurrection" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.offer_resurrection(player_guid, 0x1000000000000002, 12345, 35.0)
      DeathManager.accept_resurrection(player_guid)

      assert DeathManager.is_dead?(player_guid) == false
    end

    test "returns error when no offer pending" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      assert {:error, :no_offer} = DeathManager.accept_resurrection(player_guid)
    end

    test "returns error for living player" do
      player_guid = 0x1000000000000001
      assert {:error, :not_dead} = DeathManager.accept_resurrection(player_guid)
    end
  end

  describe "respawn_at_bindpoint/1" do
    test "respawns dead player at bindpoint" do
      player_guid = 0x1000000000000001
      zone_id = 100

      DeathManager.player_died(player_guid, zone_id, {0.0, 0.0, 0.0}, nil)

      {:ok, result} = DeathManager.respawn_at_bindpoint(player_guid)
      assert is_integer(result.zone_id)
      assert is_tuple(result.position)
      assert is_float(result.health_percent)
      assert result.resurrect_type == :bindpoint
    end

    test "player is no longer dead after respawning" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.respawn_at_bindpoint(player_guid)

      assert DeathManager.is_dead?(player_guid) == false
    end

    test "returns error for living player" do
      player_guid = 0x1000000000000001
      assert {:error, :not_dead} = DeathManager.respawn_at_bindpoint(player_guid)
    end
  end

  describe "decline_resurrection/1" do
    test "clears pending resurrection offer" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.offer_resurrection(player_guid, 0x1000000000000002, 12345, 35.0)
      DeathManager.decline_resurrection(player_guid)

      # Player is still dead, just no pending offer
      assert DeathManager.is_dead?(player_guid) == true
      assert {:error, :no_offer} = DeathManager.accept_resurrection(player_guid)
    end
  end

  describe "resurrection offer timeout" do
    test "resurrection offer has timeout" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.offer_resurrection(player_guid, 0x1000000000000002, 12345, 35.0)

      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.res_offer != nil
      assert info.res_offer.timeout_at > System.monotonic_time(:millisecond)
    end
  end

  describe "find_nearest_bindpoint/2" do
    test "returns default bindpoint when zone has no bindpoints" do
      # Zone 99999 shouldn't have any bindpoints
      result = DeathManager.find_nearest_bindpoint(99999, {0.0, 0.0, 0.0})

      assert is_map(result)
      assert is_integer(result.zone_id)
      assert is_tuple(result.position)
    end

    test "returns a bindpoint with correct structure" do
      # Use a zone that should have bindpoints (426 = Thayd)
      result = DeathManager.find_nearest_bindpoint(426, {3949.0, -855.0, -1929.0})

      assert is_map(result)
      assert Map.has_key?(result, :zone_id)
      assert Map.has_key?(result, :position)
      {x, y, z} = result.position
      assert is_float(x)
      assert is_float(y)
      assert is_float(z)
    end
  end

  describe "get_death_count/1" do
    test "returns 0 for player with no deaths" do
      player_guid = 0x1000000000000001
      assert DeathManager.get_death_count(player_guid) == 0
    end

    test "increments on death" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.get_death_count(player_guid) == 1

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      assert DeathManager.get_death_count(player_guid) == 2
    end
  end

  describe "should_apply_resurrection_sickness?/1" do
    test "returns false for fewer than 3 deaths" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      {should_apply, count} = DeathManager.should_apply_resurrection_sickness?(player_guid)
      assert should_apply == false
      assert count == 2
    end

    test "returns true for 3 or more deaths" do
      player_guid = 0x1000000000000001

      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)
      DeathManager.player_died(player_guid, 100, {0.0, 0.0, 0.0}, nil)

      {should_apply, count} = DeathManager.should_apply_resurrection_sickness?(player_guid)
      assert should_apply == true
      assert count == 3
    end
  end
end
