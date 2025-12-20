defmodule BezgelorWorld.Integration.SpellDamageTest do
  @moduledoc """
  Integration tests for spell damage → creature death flow.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CombatBroadcaster, CreatureManager, WorldManager}
  alias BezgelorCore.{AI, CreatureTemplate}

  @moduletag :integration

  describe "spell damage to creatures" do
    test "damage spell reduces creature health via CreatureManager" do
      # Spawn a Training Dummy (id 1, 100 health)
      {:ok, creature_guid} = CreatureManager.spawn_creature(1, {8000.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      # Verify creature starts at full health
      creature = CreatureManager.get_creature(creature_guid)
      assert creature.entity.health == 100

      # Simulate what SpellHandler should do: apply damage effect
      damage_amount = 25

      {:ok, :damaged, result} =
        CreatureManager.damage_creature(creature_guid, player_guid, damage_amount)

      assert result.remaining_health == 75
      assert result.max_health == 100

      # Verify creature health actually changed
      creature = CreatureManager.get_creature(creature_guid)
      assert creature.entity.health == 75
    end

    test "lethal damage kills creature and returns XP reward" do
      # Spawn a Training Dummy (id 1, 100 health, 10 XP)
      {:ok, creature_guid} = CreatureManager.spawn_creature(1, {8100.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      # Deal lethal damage
      {:ok, :killed, result} = CreatureManager.damage_creature(creature_guid, player_guid, 200)

      # Should return XP reward
      template = CreatureTemplate.get(1)
      assert result.xp_reward == template.xp_reward
      assert result.killer_guid == player_guid

      # Creature should be dead
      creature = CreatureManager.get_creature(creature_guid)
      assert AI.dead?(creature.ai)
      assert creature.entity.health == 0
    end

    test "killing creature returns creature_guid in result for death notification" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(1, {8200.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      {:ok, :killed, result} = CreatureManager.damage_creature(creature_guid, player_guid, 200)

      # Result should include creature_guid for broadcasting death
      assert Map.has_key?(result, :creature_guid)
      assert result.creature_guid == creature_guid
    end

    test "creature enters combat when damaged" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {8300.0, 8000.0, 0.0})
      player_guid = WorldManager.generate_guid(:player)

      {:ok, :damaged, _result} = CreatureManager.damage_creature(creature_guid, player_guid, 10)

      creature = CreatureManager.get_creature(creature_guid)
      assert AI.in_combat?(creature.ai)
      assert creature.ai.target_guid == player_guid
    end

    test "kill broadcasts death and XP packets to player" do
      # Spawn creature
      {:ok, creature_guid} = CreatureManager.spawn_creature(1, {8400.0, 8000.0, 0.0})

      # Register player session with self() as connection
      player_guid = WorldManager.generate_guid(:player)
      account_id = 99999
      WorldManager.register_session(account_id, 1, "TestKiller", self())
      WorldManager.set_entity_guid(account_id, player_guid)

      # Kill creature
      {:ok, :killed, result} = CreatureManager.damage_creature(creature_guid, player_guid, 200)

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
