defmodule BezgelorWorld.CombatBroadcasterDeathTest do
  @moduledoc """
  Tests for player death handling in CombatBroadcaster.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CombatBroadcaster, DeathManager}

  setup do
    # Ensure DeathManager is running
    case GenServer.whereis(DeathManager) do
      nil -> {:ok, _} = DeathManager.start_link([])
      _ -> :ok
    end

    :ok
  end

  describe "handle_player_damage/5" do
    test "triggers death when health reaches zero" do
      player_guid = 0x1000000000000001
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      attacker_guid = 0x0400000000000001

      # Start with 100 health, deal 100 damage (lethal)
      current_health = 100
      damage = 100

      CombatBroadcaster.handle_player_damage(
        player_guid,
        zone_id,
        position,
        current_health,
        damage,
        attacker_guid
      )

      # Player should now be marked as dead
      assert DeathManager.is_dead?(player_guid) == true
    end

    test "does not trigger death when health remains above zero" do
      player_guid = 0x1000000000000002
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      attacker_guid = 0x0400000000000001

      # 100 health, 50 damage (non-lethal)
      current_health = 100
      damage = 50

      CombatBroadcaster.handle_player_damage(
        player_guid,
        zone_id,
        position,
        current_health,
        damage,
        attacker_guid
      )

      # Player should NOT be dead
      assert DeathManager.is_dead?(player_guid) == false
    end

    test "records killer guid in death info" do
      player_guid = 0x1000000000000003
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      attacker_guid = 0x0400000000000005

      # Lethal damage
      CombatBroadcaster.handle_player_damage(
        player_guid,
        zone_id,
        position,
        100,
        200,
        attacker_guid
      )

      # Check death info contains killer
      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.killer_guid == attacker_guid
    end

    test "records death position" do
      player_guid = 0x1000000000000004
      zone_id = 100
      position = {123.0, 456.0, 789.0}
      attacker_guid = 0x0400000000000001

      # Lethal damage
      CombatBroadcaster.handle_player_damage(
        player_guid,
        zone_id,
        position,
        50,
        100,
        attacker_guid
      )

      # Check death info contains position
      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.position == position
    end

    test "records zone in death info" do
      player_guid = 0x1000000000000005
      zone_id = 426
      position = {0.0, 0.0, 0.0}
      attacker_guid = 0x0400000000000001

      # Lethal damage
      CombatBroadcaster.handle_player_damage(
        player_guid,
        zone_id,
        position,
        10,
        999,
        attacker_guid
      )

      # Check death info contains zone
      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.zone_id == zone_id
    end
  end

  describe "handle_environmental_death/4" do
    test "marks player as dead without killer" do
      player_guid = 0x1000000000000010
      zone_id = 100
      position = {100.0, 50.0, 200.0}
      death_type = :fall

      CombatBroadcaster.handle_environmental_death(player_guid, zone_id, position, death_type)

      assert DeathManager.is_dead?(player_guid) == true

      {:ok, info} = DeathManager.get_death_info(player_guid)
      assert info.killer_guid == nil
    end
  end
end
