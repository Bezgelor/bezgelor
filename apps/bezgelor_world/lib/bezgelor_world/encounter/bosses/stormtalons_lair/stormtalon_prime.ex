defmodule BezgelorWorld.Encounter.Bosses.StormtalonsLair.StormtalonPrime do
  @moduledoc """
  Stormtalon Prime encounter - Stormtalon's Lair (Prime Difficulty)

  Level 50 Prime version of the final boss. Features:
  - Significantly increased health and damage
  - Tighter ability timings
  - Additional Prime-only mechanics
  - More punishing coordination requirements

  Based on the hand-crafted Stormtalon example with Prime scaling.

  Data sources: client_data, existing Stormtalon script
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon" do
    boss_id 33406
    health 18_000_000
    level 50
    enrage_timer 420_000
    interrupt_armor 3

    # Phase 1: 100% - 70% health
    phase :one, health_above: 70 do
      phase_emote "Stormtalon screeches and summons lightning!"

      ability :lightning_strike, cooldown: 6_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :red
        damage 25000, type: :magic
      end

      ability :static_charge, cooldown: 12_000, target: :tank do
        debuff :static, duration: 12000, stacks: 4
        damage 18000, type: :magic
      end

      ability :static_discharge, cooldown: 20_000 do
        coordination :stack, min_players: 4, damage: 120000
        telegraph :circle, radius: 10, duration: 2500, color: :yellow
      end

      ability :tail_swipe, cooldown: 10_000, target: :farthest do
        telegraph :cone, angle: 180, length: 18, duration: 1200
        damage 35000, type: :physical
        movement :knockback, distance: 12
      end

      # Prime-only: Static field
      ability :static_field, cooldown: 25_000 do
        telegraph :circle, radius: 15, duration: 3000, color: :purple
        damage 20000, type: :magic
        debuff :grounded, duration: 8000, stacks: 1
      end
    end

    # Phase 2: 70% - 30% health
    phase :two, health_between: {30, 70} do
      inherit_phase :one
      phase_emote "The storm intensifies! Stormtalon calls forth minions!"

      ability :eye_of_the_storm, cooldown: 35_000 do
        telegraph :donut, inner_radius: 10, outer_radius: 30, duration: 3500
        damage 60000, type: :magic
        spawn :add, creature_id: 33407, count: 3, spread: true, aggro: :healer
      end

      ability :chain_lightning, cooldown: 15_000, target: :random do
        damage 20000, type: :magic
        coordination :spread, required_distance: 10, damage: 30000
      end

      # Prime-only: Lightning cage
      ability :lightning_cage, cooldown: 30_000, target: :healer do
        telegraph :circle, radius: 8, duration: 2000, color: :purple
        damage 25000, type: :magic
        debuff :caged, duration: 6000
        coordination :stack, min_players: 2, damage: 80000
      end
    end

    # Phase 3: Below 30% health
    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "Stormtalon enters a frenzy! The room crackles with energy!"
      enrage_modifier 1.6
      attack_speed_modifier 1.4

      ability :tempest, cooldown: 12_000 do
        telegraph :room_wide, duration: 2500
        damage 40000, type: :magic
        movement :knockback, distance: 18, source: :center
        safe_zone shape: :circle, radius: 8, position: :center
      end

      ability :lightning_barrage, cooldown: 8_000 do
        telegraph :cross, width: 4, length: 25, duration: 1500, color: :red
        damage 30000, type: :magic
      end

      # Prime-only: Ultimate ability
      ability :storm_caller, cooldown: 45_000 do
        telegraph :room_wide, duration: 5000
        damage 50000, type: :magic
        spawn :wave, waves: 2, delay: 3000, creature_id: 33407, count_per_wave: 4
        buff :storm_empowered, duration: 15000
      end
    end

    on_death do
      loot_table 33406
      achievement 6710  # Prime completion achievement
    end
  end
end
