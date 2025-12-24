defmodule BezgelorWorld.Integration.SpellDamageTest do
  @moduledoc """
  Integration tests for spell damage → creature death flow.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorWorld.{CombatBroadcaster, WorldManager}
  alias BezgelorCore.{AI, CreatureTemplate}

  @moduletag :integration

  # Test world key
  @test_world_id 99996
  @test_instance_id 1
  @test_world_key {@test_world_id, @test_instance_id}

  setup do
    # Start a test world instance
    world_data = %{id: @test_world_id, name: "Spell Damage Test Zone", is_test: true}

    case InstanceSupervisor.start_instance(@test_world_id, @test_instance_id, world_data) do
      {:ok, _pid} ->
        on_exit(fn ->
          InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id)
        end)

        {:ok, %{world_key: @test_world_key}}

      {:error, {:already_started, _pid}} ->
        {:ok, %{world_key: @test_world_key}}
    end
  end

  describe "spell damage to creatures" do
    test "damage spell reduces creature health via World.Instance", %{world_key: world_key} do
      # Spawn a Training Dummy (id 1, 100 health)
      {:ok, creature_guid} = Instance.spawn_creature(world_key, 1, {8000.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      # Verify creature starts at full health
      creature = Instance.get_creature(world_key, creature_guid)
      assert creature.entity.health == 100

      # Simulate what SpellHandler should do: apply damage effect
      damage_amount = 25

      {:ok, :damaged, result} =
        Instance.damage_creature(world_key, creature_guid, player_guid, damage_amount)

      assert result.remaining_health == 75
      assert result.max_health == 100

      # Verify creature health actually changed
      creature = Instance.get_creature(world_key, creature_guid)
      assert creature.entity.health == 75
    end

    test "lethal damage kills creature and returns XP reward", %{world_key: world_key} do
      # Spawn a Training Dummy (id 1, 100 health, 10 XP)
      {:ok, creature_guid} = Instance.spawn_creature(world_key, 1, {8100.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      # Deal lethal damage
      {:ok, :killed, result} = Instance.damage_creature(world_key, creature_guid, player_guid, 200)

      # Should return XP reward
      template = CreatureTemplate.get(1)
      assert result.xp_reward == template.xp_reward
      assert result.killer_guid == player_guid

      # Creature should be dead
      creature = Instance.get_creature(world_key, creature_guid)
      assert AI.dead?(creature.ai)
      assert creature.entity.health == 0
    end

    test "killing creature returns creature_guid in result for death notification", %{
      world_key: world_key
    } do
      {:ok, creature_guid} = Instance.spawn_creature(world_key, 1, {8200.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      {:ok, :killed, result} = Instance.damage_creature(world_key, creature_guid, player_guid, 200)

      # Result should include creature_guid for broadcasting death
      assert Map.has_key?(result, :creature_guid)
      assert result.creature_guid == creature_guid
    end

    test "creature enters combat when damaged", %{world_key: world_key} do
      {:ok, creature_guid} = Instance.spawn_creature(world_key, 2, {8300.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      {:ok, :damaged, _result} =
        Instance.damage_creature(world_key, creature_guid, player_guid, 10)

      creature = Instance.get_creature(world_key, creature_guid)
      assert AI.in_combat?(creature.ai)
      assert creature.ai.target_guid == player_guid
    end

    test "kill broadcasts death and XP packets to player", %{world_key: world_key} do
      # Spawn creature
      {:ok, creature_guid} = Instance.spawn_creature(world_key, 1, {8400.0, 8000.0, 0.0})

      # Register player session with self() as connection
      player_guid = WorldManager.generate_guid(:player)
      account_id = 99999
      WorldManager.register_session(account_id, 1, "TestKiller", self())
      WorldManager.set_entity_guid(account_id, player_guid)

      # Kill creature
      {:ok, :killed, result} = Instance.damage_creature(world_key, creature_guid, player_guid, 200)

      # Broadcast death and XP using CombatBroadcaster
      CombatBroadcaster.broadcast_entity_death(result.creature_guid, player_guid, [player_guid])
      CombatBroadcaster.send_kill_rewards(player_guid, result.creature_guid, result)

      # Should receive death packet
      assert_receive {:send_packet, :server_entity_death, death_data}, 1000
      assert byte_size(death_data) == 16

      # Should receive XP packet
      assert_receive {:send_packet, :server_xp_gain, _xp_data}, 1000
    end
  end
end
