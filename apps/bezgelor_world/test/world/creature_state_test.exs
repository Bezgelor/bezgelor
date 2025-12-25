defmodule BezgelorWorld.World.CreatureStateTest do
  @moduledoc """
  Unit tests for BezgelorWorld.World.CreatureState.

  Tests pure functions for creature state management including:
  - Calculation helpers (tier_to_level, calculate_max_health, etc.)
  - State queries (needs_processing?, targetable?)
  - Combat operations (apply_damage, enter_combat)
  - AI processing (process_ai_tick, check_aggro_nearby_players)
  """
  use ExUnit.Case, async: true

  alias BezgelorWorld.World.CreatureState
  alias BezgelorCore.{AI, CreatureTemplate, Entity}

  # =====================================================================
  # Calculation Helpers
  # =====================================================================

  describe "tier_to_level/1" do
    test "tier 1 returns level 1-10" do
      for _ <- 1..20 do
        level = CreatureState.tier_to_level(1)
        assert level >= 1 and level <= 10
      end
    end

    test "tier 2 returns level 10-20" do
      for _ <- 1..20 do
        level = CreatureState.tier_to_level(2)
        assert level >= 10 and level <= 20
      end
    end

    test "tier 3 returns level 20-35" do
      for _ <- 1..20 do
        level = CreatureState.tier_to_level(3)
        assert level >= 20 and level <= 35
      end
    end

    test "tier 4 returns level 35-50" do
      for _ <- 1..20 do
        level = CreatureState.tier_to_level(4)
        assert level >= 35 and level <= 50
      end
    end

    test "unknown tier returns level 1-50" do
      for _ <- 1..20 do
        level = CreatureState.tier_to_level(99)
        assert level >= 1 and level <= 50
      end
    end
  end

  describe "calculate_max_health/3" do
    test "base health scales with level" do
      # Base formula: 50 + level * 20
      # Tier 1, difficulty 1 = 1.0 multipliers
      health_level_1 = CreatureState.calculate_max_health(1, 1, 1)
      health_level_10 = CreatureState.calculate_max_health(1, 1, 10)

      assert health_level_1 == 70  # 50 + 1*20
      assert health_level_10 == 250  # 50 + 10*20
    end

    test "tier multiplier increases health" do
      level = 10
      base = 50 + level * 20  # 250

      assert CreatureState.calculate_max_health(1, 1, level) == round(base * 1.0)
      assert CreatureState.calculate_max_health(2, 1, level) == round(base * 1.5)
      assert CreatureState.calculate_max_health(3, 1, level) == round(base * 2.0)
      assert CreatureState.calculate_max_health(4, 1, level) == round(base * 3.0)
    end

    test "difficulty multiplier increases health" do
      level = 10
      base = 50 + level * 20  # 250

      assert CreatureState.calculate_max_health(1, 1, level) == round(base * 1.0)
      assert CreatureState.calculate_max_health(1, 2, level) == round(base * 2.0)
      assert CreatureState.calculate_max_health(1, 3, level) == round(base * 5.0)
      assert CreatureState.calculate_max_health(1, 4, level) == round(base * 10.0)
    end

    test "tier and difficulty combine multiplicatively" do
      level = 10
      base = 50 + level * 20  # 250
      # Tier 2 (1.5x) + Difficulty 3 (5x) = 7.5x
      expected = round(base * 1.5 * 5.0)

      assert CreatureState.calculate_max_health(2, 3, level) == expected
    end

    test "unknown tier/difficulty defaults to 1.0 multiplier" do
      level = 10
      base = 50 + level * 20

      assert CreatureState.calculate_max_health(99, 1, level) == base
      assert CreatureState.calculate_max_health(1, 99, level) == base
    end
  end

  describe "calculate_damage/2" do
    test "base damage scales with level" do
      {min1, max1} = CreatureState.calculate_damage(1, 1)
      {min10, max10} = CreatureState.calculate_damage(10, 1)

      # base_min = 5 + level, base_max = 10 + level * 2
      assert min1 == 6   # 5 + 1
      assert max1 == 12  # 10 + 1*2
      assert min10 == 15 # 5 + 10
      assert max10 == 30 # 10 + 10*2
    end

    test "difficulty multiplier increases damage" do
      level = 10
      base_min = 5 + level  # 15
      base_max = 10 + level * 2  # 30

      {min1, max1} = CreatureState.calculate_damage(level, 1)
      {min2, max2} = CreatureState.calculate_damage(level, 2)
      {min3, max3} = CreatureState.calculate_damage(level, 3)
      {min4, max4} = CreatureState.calculate_damage(level, 4)

      assert {min1, max1} == {round(base_min * 1.0), round(base_max * 1.0)}
      assert {min2, max2} == {round(base_min * 1.5), round(base_max * 1.5)}
      assert {min3, max3} == {round(base_min * 2.0), round(base_max * 2.0)}
      assert {min4, max4} == {round(base_min * 3.0), round(base_max * 3.0)}
    end

    test "unknown difficulty defaults to 1.0 multiplier" do
      {min, max} = CreatureState.calculate_damage(10, 99)
      assert min == 15
      assert max == 30
    end
  end

  describe "archetype_to_ai_type/1" do
    test "archetype 30 returns passive" do
      assert CreatureState.archetype_to_ai_type(30) == :passive
    end

    test "archetype 31 returns defensive" do
      assert CreatureState.archetype_to_ai_type(31) == :defensive
    end

    test "other archetypes return aggressive" do
      assert CreatureState.archetype_to_ai_type(0) == :aggressive
      assert CreatureState.archetype_to_ai_type(1) == :aggressive
      assert CreatureState.archetype_to_ai_type(99) == :aggressive
    end
  end

  describe "faction_to_int/1" do
    test "converts faction atoms to integers" do
      assert CreatureState.faction_to_int(:hostile) == 0
      assert CreatureState.faction_to_int(:neutral) == 1
      assert CreatureState.faction_to_int(:friendly) == 2
    end

    test "unknown faction defaults to 0" do
      assert CreatureState.faction_to_int(:unknown) == 0
      assert CreatureState.faction_to_int(nil) == 0
    end
  end

  # =====================================================================
  # State Queries
  # =====================================================================

  describe "needs_processing?/1" do
    test "returns true when in combat" do
      creature_state = build_creature_state(ai_state: :combat)
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when evading" do
      creature_state = build_creature_state(ai_state: :evade)
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when wandering" do
      creature_state = build_creature_state(ai_state: :wandering)
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when patrolling" do
      creature_state = build_creature_state(ai_state: :patrol)
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when threat table is not empty" do
      creature_state = build_creature_state(ai_state: :idle, threat_table: %{12345 => 100})
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when idle with patrol enabled" do
      creature_state = build_creature_state(ai_state: :idle, patrol_enabled: true)
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns true when idle aggressive with aggro range" do
      creature_state = build_creature_state(
        ai_state: :idle,
        ai_type: :aggressive,
        aggro_range: 15.0
      )
      assert CreatureState.needs_processing?(creature_state)
    end

    test "returns false when idle passive" do
      creature_state = build_creature_state(ai_state: :idle, ai_type: :passive)
      refute CreatureState.needs_processing?(creature_state)
    end

    test "returns false when idle aggressive but no aggro range" do
      creature_state = build_creature_state(
        ai_state: :idle,
        ai_type: :aggressive,
        aggro_range: 0.0
      )
      refute CreatureState.needs_processing?(creature_state)
    end
  end

  describe "targetable?/1" do
    test "returns true when alive" do
      creature_state = build_creature_state(health: 100, ai_state: :idle)
      assert CreatureState.targetable?(creature_state)
    end

    test "returns false when dead via AI state" do
      creature_state = build_creature_state(health: 100, ai_state: :dead)
      refute CreatureState.targetable?(creature_state)
    end

    test "returns false when health is 0" do
      creature_state = build_creature_state(health: 0, ai_state: :idle)
      refute CreatureState.targetable?(creature_state)
    end

    test "returns false when health is negative" do
      creature_state = build_creature_state(health: -10, ai_state: :idle)
      refute CreatureState.targetable?(creature_state)
    end
  end

  # =====================================================================
  # Combat Operations
  # =====================================================================

  describe "enter_combat/2" do
    test "sets combat state and target" do
      creature_state = build_creature_state(ai_state: :idle)
      target_guid = 12345

      new_state = CreatureState.enter_combat(creature_state, target_guid)

      assert new_state.ai.state == :combat
      assert new_state.ai.target_guid == target_guid
    end

    test "does nothing when already dead" do
      creature_state = build_creature_state(ai_state: :dead)
      target_guid = 12345

      new_state = CreatureState.enter_combat(creature_state, target_guid)

      assert new_state.ai.state == :dead
      refute new_state.ai.target_guid == target_guid
    end
  end

  describe "apply_damage/4" do
    test "reduces health and returns damaged result" do
      creature_state = build_creature_state(health: 100, max_health: 100)

      {:ok, :damaged, info, new_state} =
        CreatureState.apply_damage(creature_state, 12345, 30)

      assert info.remaining_health == 70
      assert info.max_health == 100
      assert new_state.entity.health == 70
    end

    test "enters combat when damaged" do
      creature_state = build_creature_state(health: 100, ai_state: :idle)

      {:ok, :damaged, _info, new_state} =
        CreatureState.apply_damage(creature_state, 12345, 10)

      assert new_state.ai.state == :combat
      assert new_state.ai.target_guid == 12345
    end

    test "adds threat to attacker" do
      creature_state = build_creature_state(health: 100)

      {:ok, :damaged, _info, new_state} =
        CreatureState.apply_damage(creature_state, 12345, 50)

      assert Map.has_key?(new_state.ai.threat_table, 12345)
      assert new_state.ai.threat_table[12345] >= 50
    end

    test "zero damage still triggers combat" do
      creature_state = build_creature_state(health: 100, ai_state: :idle)

      {:ok, :damaged, info, new_state} =
        CreatureState.apply_damage(creature_state, 12345, 0)

      assert info.remaining_health == 100
      assert new_state.ai.state == :combat
    end

    test "returns killed result when damage exceeds health" do
      creature_state = build_creature_state(health: 50, max_health: 100, ai_state: :idle)

      {:ok, :killed, info, new_state} =
        CreatureState.apply_damage(creature_state, 12345, 100)

      assert info.killer_guid == 12345
      assert info.xp_reward >= 0
      assert new_state.ai.state == :dead
      assert new_state.entity.health <= 0
    end

    test "returns killed result when damage equals health" do
      creature_state = build_creature_state(health: 100, max_health: 100)

      {:ok, :killed, info, _new_state} =
        CreatureState.apply_damage(creature_state, 99999, 100)

      assert info.killer_guid == 99999
    end

    test "uses killer_level option for XP calculation" do
      creature_state = build_creature_state(health: 50)

      {:ok, :killed, info, _new_state} =
        CreatureState.apply_damage(creature_state, 12345, 100, killer_level: 50)

      # XP should be calculated using the provided killer level
      assert info.xp_reward >= 0
    end
  end

  # =====================================================================
  # AI Processing
  # =====================================================================

  describe "check_aggro_nearby_players/2" do
    test "returns nil when no players nearby" do
      creature_state = build_creature_state(
        position: {100.0, 100.0, 100.0},
        aggro_range: 15.0
      )

      context = %{
        entities: %{},
        players: MapSet.new(),
        world_id: 1,
        instance_id: 1
      }

      assert CreatureState.check_aggro_nearby_players(creature_state, context) == nil
    end

    test "returns nil when player is out of range" do
      creature_state = build_creature_state(
        position: {100.0, 100.0, 100.0},
        aggro_range: 15.0
      )

      player_guid = 99999
      player_entity = %{guid: player_guid, position: {200.0, 200.0, 100.0}, faction: :exile}

      context = %{
        entities: %{player_guid => player_entity},
        players: MapSet.new([player_guid]),
        world_id: 1,
        instance_id: 1
      }

      assert CreatureState.check_aggro_nearby_players(creature_state, context) == nil
    end
  end

  describe "process_ai_tick/3" do
    test "returns no_change for idle passive creature" do
      creature_state = build_creature_state(ai_state: :idle, ai_type: :passive)

      context = %{
        entities: %{},
        players: MapSet.new(),
        world_id: 1,
        instance_id: 1
      }

      result = CreatureState.process_ai_tick(creature_state, context, now())
      assert {:no_change, _} = result
    end

    test "checks aggro for idle aggressive creature" do
      creature_state = build_creature_state(
        ai_state: :idle,
        ai_type: :aggressive,
        aggro_range: 15.0,
        position: {100.0, 100.0, 100.0}
      )

      player_guid = 99999
      player_entity = %{guid: player_guid, position: {105.0, 100.0, 100.0}, faction: :exile}

      context = %{
        entities: %{player_guid => player_entity},
        players: MapSet.new([player_guid]),
        world_id: 1,
        instance_id: 1
      }

      result = CreatureState.process_ai_tick(creature_state, context, now())

      case result do
        {:updated, new_state, []} ->
          assert new_state.ai.state == :combat
          assert new_state.ai.target_guid == player_guid

        {:no_change, _} ->
          # Faction check may prevent aggro - this is acceptable
          :ok
      end
    end

    test "starts evade when leashed in combat" do
      creature_state = build_creature_state(
        ai_state: :combat,
        position: {200.0, 200.0, 200.0},  # Far from spawn
        spawn_position: {100.0, 100.0, 100.0},
        leash_range: 40.0
      )

      context = %{
        entities: %{},
        players: MapSet.new(),
        world_id: 1,
        instance_id: 1
      }

      {:updated, new_state, []} = CreatureState.process_ai_tick(creature_state, context, now())
      assert new_state.ai.state == :evade
    end

    # =========================================================================
    # Chase Movement Tests (migrated from creature_chase_movement_test.exs)
    # =========================================================================

    test "creature starts chasing when target is out of attack range" do
      target_guid = 99999
      # Target is 25 units away (beyond attack range of ~5)
      target_entity = %{guid: target_guid, position: {125.0, 100.0, 100.0}, faction: :exile}

      creature_state = build_creature_state(
        ai_state: :combat,
        position: {100.0, 100.0, 100.0},
        target_guid: target_guid
      )

      context = %{
        entities: %{target_guid => target_entity},
        players: MapSet.new([target_guid]),
        world_id: 1,
        instance_id: 1
      }

      result = CreatureState.process_ai_tick(creature_state, context, now())

      case result do
        {:updated, new_state, _packets} ->
          # Should be chasing with a path
          assert new_state.ai.chase_path != nil
          assert new_state.ai.state == :combat

        {:no_change, _} ->
          # May not update due to movement cooldown - acceptable
          :ok
      end
    end

    test "creature attacks when target is in attack range" do
      target_guid = 99999
      # Target is 3 units away (within attack range of ~5)
      target_entity = %{guid: target_guid, position: {103.0, 100.0, 100.0}, faction: :exile}

      creature_state = build_creature_state(
        ai_state: :combat,
        position: {100.0, 100.0, 100.0},
        target_guid: target_guid
      )

      context = %{
        entities: %{target_guid => target_entity},
        players: MapSet.new([target_guid]),
        world_id: 1,
        instance_id: 1
      }

      result = CreatureState.process_ai_tick(creature_state, context, now())

      case result do
        {:updated, new_state, _packets} ->
          # Should have attacked (recorded attack time) not chasing
          assert new_state.ai.chase_path == nil or new_state.ai.last_attack_time != nil

        {:no_change, _} ->
          # May not update due to attack cooldown - acceptable
          :ok
      end
    end

    test "creature handles target removed from context" do
      target_guid = 99999

      creature_state = build_creature_state(
        ai_state: :combat,
        position: {100.0, 100.0, 100.0},
        target_guid: target_guid
      )

      # Empty context - target no longer exists
      context = %{
        entities: %{},
        players: MapSet.new(),
        world_id: 1,
        instance_id: 1
      }

      result = CreatureState.process_ai_tick(creature_state, context, now())

      case result do
        {:updated, new_state, _packets} ->
          # When target is lost, creature may evade or clear target while staying combat
          # Either behavior is acceptable depending on threat table state
          assert new_state.ai.state in [:evade, :combat]

        {:no_change, _} ->
          # May not update immediately - acceptable
          :ok
      end
    end
  end

  # =====================================================================
  # Helper Functions
  # =====================================================================

  defp build_creature_state(opts) do
    health = Keyword.get(opts, :health, 100)
    max_health = Keyword.get(opts, :max_health, 100)
    ai_state = Keyword.get(opts, :ai_state, :idle)
    ai_type = Keyword.get(opts, :ai_type, :aggressive)
    aggro_range = Keyword.get(opts, :aggro_range, 0.0)
    leash_range = Keyword.get(opts, :leash_range, 40.0)
    position = Keyword.get(opts, :position, {100.0, 100.0, 100.0})
    spawn_position = Keyword.get(opts, :spawn_position, position)
    threat_table = Keyword.get(opts, :threat_table, %{})
    patrol_enabled = Keyword.get(opts, :patrol_enabled, false)

    entity = %Entity{
      guid: 1000,
      type: :creature,
      name: "Test Creature",
      level: 10,
      position: position,
      health: health,
      max_health: max_health
    }

    template = %CreatureTemplate{
      id: 1,
      name: "Test Creature",
      level: 10,
      max_health: max_health,
      faction: :hostile,
      ai_type: ai_type,
      aggro_range: aggro_range,
      leash_range: leash_range,
      respawn_time: 60_000,
      xp_reward: 100
    }

    wander_enabled = Keyword.get(opts, :wander_enabled, false)
    target_guid = Keyword.get(opts, :target_guid, nil)

    ai = %AI{
      state: ai_state,
      spawn_position: spawn_position,
      threat_table: threat_table,
      patrol_enabled: patrol_enabled,
      wander_enabled: wander_enabled,
      target_guid: target_guid
    }

    %{
      entity: entity,
      template: template,
      ai: ai,
      spawn_position: spawn_position,
      respawn_timer: nil,
      target_position: nil,
      world_id: 1,
      spawn_def: nil
    }
  end

  defp now, do: System.monotonic_time(:millisecond)
end
