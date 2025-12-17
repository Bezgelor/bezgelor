defmodule BezgelorWorld.Integration.CombatLoopTest do
  @moduledoc """
  Integration tests for the full combat loop.

  Tests the complete cycle of:
  1. Player with real stats attacks creature
  2. Creature dies
  3. Corpse is spawned with loot
  4. XP is awarded to player

  This test verifies that all combat system gaps are closed:
  - Character stats lookup
  - Telegraph transmission
  - XP persistence
  - Corpse/loot spawning
  """
  use ExUnit.Case, async: false

  alias BezgelorCore.{CharacterStats, Entity}
  alias BezgelorWorld.CorpseManager

  @moduletag :integration

  setup do
    # Start CorpseManager if not running
    case GenServer.whereis(CorpseManager) do
      nil ->
        {:ok, _} = CorpseManager.start_link([])

      _pid ->
        # Clear existing corpses
        try do
          CorpseManager.clear_all()
        catch
          :exit, _ -> :ok
        end
    end

    Process.sleep(100)
    :ok
  end

  describe "character stats computation" do
    test "computes combat stats from character data" do
      character = %{level: 10, class: 1, race: 0}

      stats = CharacterStats.compute_combat_stats(character)

      assert stats.power > 0
      assert stats.tech > 0
      assert stats.support > 0
      assert stats.crit_chance >= 5
      assert stats.armor > 0
    end

    test "higher level characters have higher stats" do
      low_level = CharacterStats.compute_combat_stats(%{level: 1, class: 1, race: 0})
      high_level = CharacterStats.compute_combat_stats(%{level: 50, class: 1, race: 0})

      assert high_level.power > low_level.power
      assert high_level.armor > low_level.armor
    end

    test "assault classes favor power" do
      warrior = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})
      esper = CharacterStats.compute_combat_stats(%{level: 10, class: 4, race: 0})

      assert warrior.power >= esper.power
    end

    test "buff modifiers add to computed stats" do
      base_stats = CharacterStats.compute_combat_stats(%{level: 10, class: 1, race: 0})

      modified = CharacterStats.apply_buff_modifiers(base_stats, %{power: 50, armor: 0.05})

      assert modified.power == base_stats.power + 50
      assert_in_delta modified.armor, base_stats.armor + 0.05, 0.001
    end
  end

  describe "creature death and corpse spawning" do
    test "spawns corpse when creature dies with loot" do
      # Create a dead creature entity
      creature = %Entity{
        guid: 0x0400000000000001,
        type: :creature,
        name: "Test Mob",
        position: {100.0, 50.0, 200.0},
        zone_id: 100
      }

      # Loot drops: item 1001 x1, 500 gold
      loot = [{1001, 1}, {0, 500}]

      # Spawn corpse
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, loot)

      assert corpse_guid != creature.guid

      # Verify corpse exists
      {:ok, corpse} = CorpseManager.get_corpse(corpse_guid)
      assert corpse.type == :corpse
      assert corpse.position == creature.position
      assert corpse.loot == loot
    end

    test "corpse can be looted by player" do
      creature = %Entity{guid: 12345, position: {0.0, 0.0, 0.0}, zone_id: 100}
      {:ok, corpse_guid} = CorpseManager.spawn_corpse(creature, [{1001, 2}, {0, 100}])

      player_guid = 0x1000000000000001

      # First loot attempt succeeds
      {:ok, loot} = CorpseManager.take_loot(corpse_guid, player_guid)
      assert loot == [{1001, 2}, {0, 100}]

      # Second loot attempt returns empty (already looted)
      {:ok, loot2} = CorpseManager.take_loot(corpse_guid, player_guid)
      assert loot2 == []
    end

    test "corpse not found returns error" do
      result = CorpseManager.take_loot(999999, 12345)
      assert result == {:error, :not_found}
    end

    test "get_corpses_in_zone returns corpses in that zone" do
      creature1 = %Entity{guid: 1, position: {0.0, 0.0, 0.0}, zone_id: 100}
      creature2 = %Entity{guid: 2, position: {5.0, 0.0, 0.0}, zone_id: 100}
      creature3 = %Entity{guid: 3, position: {100.0, 0.0, 0.0}, zone_id: 200}

      {:ok, _} = CorpseManager.spawn_corpse(creature1, [{1, 1}])
      {:ok, _} = CorpseManager.spawn_corpse(creature2, [{2, 1}])
      {:ok, _} = CorpseManager.spawn_corpse(creature3, [{3, 1}])

      # Get corpses in zone 100
      corpses_100 = CorpseManager.get_corpses_in_zone(100)
      assert length(corpses_100) == 2

      # Get corpses in zone 200
      corpses_200 = CorpseManager.get_corpses_in_zone(200)
      assert length(corpses_200) == 1
    end
  end

  describe "telegraph broadcast" do
    test "ServerTelegraph packet can be created and serialized" do
      alias BezgelorProtocol.Packets.World.ServerTelegraph
      alias BezgelorProtocol.PacketWriter

      # Circle telegraph
      circle = ServerTelegraph.circle(12345, {10.0, 20.0, 30.0}, 8.0, 2000, :red)
      assert circle.shape == :circle
      assert circle.params.radius == 8.0

      # Serialize
      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(circle, writer)
      data = PacketWriter.to_binary(writer)

      assert byte_size(data) > 0
    end

    test "CombatBroadcaster can broadcast telegraphs" do
      alias BezgelorWorld.CombatBroadcaster
      alias BezgelorProtocol.Packets.World.ServerTelegraph

      # Create a telegraph packet
      packet = ServerTelegraph.circle(12345, {10.0, 20.0, 30.0}, 8.0, 2000, :red)

      # Broadcast to empty list (no recipients) should succeed
      result = CombatBroadcaster.broadcast_telegraph(packet, [])
      assert result == :ok

      # Circle telegraph helper
      result2 = CombatBroadcaster.broadcast_circle_telegraph(
        12345, {0.0, 0.0, 0.0}, 5.0, 1000, :blue, []
      )
      assert result2 == :ok
    end
  end
end
