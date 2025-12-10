defmodule BezgelorWorld.CombatBroadcasterTest do
  @moduledoc """
  Tests for CombatBroadcaster module.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.{CombatBroadcaster, WorldManager}

  @moduletag :integration

  setup do
    # Register a test player session with self() as connection PID
    account_id = 12345
    player_guid = WorldManager.generate_guid(:player)
    WorldManager.register_session(account_id, 1, "TestPlayer", self())
    WorldManager.set_entity_guid(account_id, player_guid)

    {:ok, player_guid: player_guid, account_id: account_id}
  end

  describe "broadcast_entity_death/3" do
    test "sends death packet to player", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)

      CombatBroadcaster.broadcast_entity_death(creature_guid, player_guid, [player_guid])

      assert_receive {:send_packet, :server_entity_death, packet_data}, 1000
      assert is_binary(packet_data)
      # Death packet should contain creature_guid and killer_guid (16 bytes = 2 uint64)
      assert byte_size(packet_data) == 16
    end
  end

  describe "send_xp_gain/4" do
    test "sends XP packet to player", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)

      CombatBroadcaster.send_xp_gain(player_guid, 100, :kill, creature_guid)

      assert_receive {:send_packet, :server_xp_gain, packet_data}, 1000
      assert is_binary(packet_data)
    end
  end

  describe "send_spell_effect/5" do
    test "sends damage effect packet to player", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)
      effect = %{type: :damage, amount: 50, is_crit: false}

      CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])

      assert_receive {:send_packet, :server_spell_effect, packet_data}, 1000
      assert is_binary(packet_data)
      # Effect packet: caster(8) + target(8) + spell_id(4) + type(1) + amount(4) + flags(1) = 26 bytes
      assert byte_size(packet_data) == 26
    end

    test "sends critical damage effect", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)
      effect = %{type: :damage, amount: 100, is_crit: true}

      CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])

      assert_receive {:send_packet, :server_spell_effect, _packet_data}, 1000
    end
  end

  describe "send_kill_rewards/3" do
    test "sends XP packet when rewards include XP", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)
      rewards = %{xp_reward: 50, items: [], gold: 0}

      CombatBroadcaster.send_kill_rewards(player_guid, creature_guid, rewards)

      assert_receive {:send_packet, :server_xp_gain, _packet_data}, 1000
    end

    test "does not send XP packet when XP is 0", %{player_guid: player_guid} do
      creature_guid = WorldManager.generate_guid(:creature)
      rewards = %{xp_reward: 0, items: [], gold: 0}

      CombatBroadcaster.send_kill_rewards(player_guid, creature_guid, rewards)

      refute_receive {:send_packet, :server_xp_gain, _packet_data}, 100
    end
  end
end
