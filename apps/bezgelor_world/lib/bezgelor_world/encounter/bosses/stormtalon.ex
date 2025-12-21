defmodule BezgelorWorld.Encounter.Bosses.Stormtalon do
  @moduledoc """
  Stormtalon boss encounter from Stormtalon's Lair dungeon.

  A three-phase encounter featuring:
  - Lightning-based attacks with telegraphs
  - Add spawns during eye of the storm
  - Increasing damage in final phase

  ## Strategy
  Phase 1 (100-70%): Avoid lightning strikes, stack for Static Discharge
  Phase 2 (70-30%): Kill adds during Eye of the Storm, avoid donut AoE
  Phase 3 (<30%): Burn boss, avoid room-wide tempest, use knockback immunity
  """
  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon" do
    boss_id(1001)
    health(500_000)
    level(20)
    enrage_timer(480_000)
    interrupt_armor(2)

    # Phase 1: 100% - 70% health
    phase :one, health_above: 70 do
      phase_emote("Stormtalon screeches and summons lightning!")

      ability :lightning_strike, cooldown: 8000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :red)
        damage(5000, type: :magic)
      end

      ability :static_charge, cooldown: 15000, target: :tank do
        debuff(:static, duration: 10000, stacks: 3)
        damage(3000, type: :magic)
      end

      ability :static_discharge, cooldown: 25000 do
        coordination(:stack, min_players: 3, damage: 30000)
        telegraph(:circle, radius: 8, duration: 3000, color: :yellow)
      end

      ability :tail_swipe, cooldown: 12000, target: :farthest do
        telegraph(:cone, angle: 180, length: 15, duration: 1500)
        damage(8000, type: :physical)
        movement(:knockback, distance: 10)
      end
    end

    # Phase 2: 70% - 30% health
    phase :two, health_between: {30, 70} do
      inherit_phase(:one)
      phase_emote("The storm intensifies! Stormtalon calls forth minions!")

      ability :eye_of_the_storm, cooldown: 45000 do
        telegraph(:donut, inner_radius: 8, outer_radius: 25, duration: 4000)
        damage(15000, type: :magic)
        spawn(:add, creature_id: 2001, count: 2, spread: true, aggro: :healer)
      end

      ability :chain_lightning, cooldown: 20000, target: :random do
        target(:chain, initial: :random, jumps: 4, range: 8)
        damage(4000, type: :magic)
        coordination(:spread, required_distance: 8, damage: 6000)
      end
    end

    # Phase 3: Below 30% health
    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("Stormtalon enters a frenzy! The room crackles with energy!")
      enrage_modifier(1.5)
      attack_speed_modifier(1.3)

      ability :tempest, cooldown: 15000 do
        telegraph(:room_wide, duration: 3000)
        damage(10000, type: :magic)
        movement(:knockback, distance: 15, source: :center)
        safe_zone(shape: :circle, radius: 6, position: :center)
      end

      ability :lightning_barrage, cooldown: 8000 do
        telegraph_pattern :sequential, delay: 500 do
          pattern_telegraph(:circle, radius: 4, duration: 1000)
          pattern_telegraph(:circle, radius: 4, duration: 1000, offset: {5, 0, 0})
          pattern_telegraph(:circle, radius: 4, duration: 1000, offset: {-5, 0, 0})
        end

        damage(6000, type: :magic)
      end
    end

    on_death do
      loot_table(1001)
      achievement(5001)
    end
  end
end
