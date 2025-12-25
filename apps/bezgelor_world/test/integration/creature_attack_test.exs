defmodule BezgelorWorld.Integration.CreatureAttackTest do
  @moduledoc """
  Integration tests for creature AI attacks on players.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CombatBroadcaster, WorldManager}
  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  @moduletag :integration

  setup do
    # Create unique zone instance for this test
    zone_id = System.unique_integer([:positive])
    instance_id = 1

    zone_data = %{
      id: zone_id,
      name: "Test Combat Zone",
      min_level: 1,
      max_level: 50
    }

    {:ok, _pid} = InstanceSupervisor.start_instance(zone_id, instance_id, zone_data)

    # Register a test player session with self() as connection PID
    account_id = 88888
    player_guid = WorldManager.generate_guid(:player)
    WorldManager.register_session(account_id, zone_id, "TestVictim", self())
    WorldManager.set_entity_guid(account_id, player_guid)

    # Add player entity to zone instance
    player_entity = %Entity{
      guid: player_guid,
      type: :player,
      name: "TestVictim",
      level: 10,
      position: {8500.0, 8500.0, 0.0},
      health: 500,
      max_health: 500
    }

    Instance.add_entity({zone_id, instance_id}, player_entity)

    on_exit(fn ->
      Instance.remove_entity({zone_id, instance_id}, player_guid)
      InstanceSupervisor.stop_instance(zone_id, instance_id)
    end)

    {:ok,
     player_guid: player_guid,
     player_entity: player_entity,
     account_id: account_id,
     zone_id: zone_id,
     instance_id: instance_id}
  end

  describe "creature attacks on players" do
    test "CombatBroadcaster.send_spell_effect sends damage to player", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)
      effect = %{type: :damage, amount: 25, is_crit: false}

      CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])

      assert_receive {:send_packet, :server_spell_effect, packet_data}, 1000
      assert byte_size(packet_data) == 26
    end

    test "player health can be reduced via ZoneInstance", %{
      player_guid: player_guid,
      zone_id: zone_id,
      instance_id: instance_id
    } do
      # Apply damage to player
      :ok =
        Instance.update_entity({zone_id, instance_id}, player_guid, fn entity ->
          Entity.apply_damage(entity, 100)
        end)

      # Verify health reduced
      {:ok, player} = Instance.get_entity({zone_id, instance_id}, player_guid)
      assert player.health == 400
    end

    test "player death is detected when health reaches 0", %{
      player_guid: player_guid,
      zone_id: zone_id,
      instance_id: instance_id
    } do
      # Apply lethal damage
      :ok =
        Instance.update_entity({zone_id, instance_id}, player_guid, fn entity ->
          Entity.apply_damage(entity, 1000)
        end)

      # Verify death
      {:ok, player} = Instance.get_entity({zone_id, instance_id}, player_guid)
      assert player.health == 0
      assert Entity.dead?(player)
    end

    test "death broadcast sent when player dies", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)

      # Simulate player death broadcast
      CombatBroadcaster.broadcast_entity_death(player_guid, creature_guid, [player_guid])

      assert_receive {:send_packet, :server_entity_death, packet_data}, 1000
      assert byte_size(packet_data) == 16
    end

    test "respawn restores player health and broadcasts", %{
      player_guid: player_guid,
      zone_id: zone_id,
      instance_id: instance_id
    } do
      # First kill the player
      :ok =
        Instance.update_entity({zone_id, instance_id}, player_guid, fn entity ->
          Entity.apply_damage(entity, 1000)
        end)

      {:ok, dead_player} = Instance.get_entity({zone_id, instance_id}, player_guid)
      assert dead_player.health == 0

      # Now respawn
      :ok =
        Instance.update_entity({zone_id, instance_id}, player_guid, fn entity ->
          Entity.respawn(entity)
        end)

      {:ok, respawned_player} = Instance.get_entity({zone_id, instance_id}, player_guid)
      assert respawned_player.health == 500
      assert respawned_player.is_dead == false

      # Test respawn broadcast
      {x, y, z} = respawned_player.position
      CombatBroadcaster.send_respawn(player_guid, {x, y, z}, 500, 500, [player_guid])

      assert_receive {:send_packet, :server_respawn, packet_data}, 1000
      # Respawn packet: guid(8) + x(4) + y(4) + z(4) + health(4) + max_health(4) = 28 bytes
      assert byte_size(packet_data) == 28
    end
  end
end
