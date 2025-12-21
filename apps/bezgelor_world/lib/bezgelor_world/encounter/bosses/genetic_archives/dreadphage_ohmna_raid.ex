defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.DreadphageOhmnaRaid do
  @moduledoc """
  Dreadphage Ohmna encounter - Genetic Archives (Final Boss - 20-man Raid)

  The ultimate genetic horror and final boss of Genetic Archives. Features:
  - Tentacle phases with add management
  - Devour mechanic requiring rescue
  - Genetic Storm room-wide devastation
  - Extinction Protocol final phase wipe mechanic

  ## Strategy
  Phase 1 (100-75%): Tank positions for cleave, dodge Tentacle Slam
  Phase 2 (75-50%): Kill tentacles quickly, rescue Devour targets
  Phase 3 (50-25%): Heal through Genetic Storm, kill adds
  Phase 4 (<25%): Race against Extinction Protocol

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Dreadphage Ohmna" do
    boss_id(60006)
    health(65_000_000)
    level(50)
    enrage_timer(720_000)
    interrupt_armor(5)

    phase :one, health_above: 75 do
      phase_emote("YOU DARE ENTER MY DOMAIN? YOU WILL BE CONSUMED!")

      ability :genetic_assault, cooldown: 8_000, target: :tank do
        telegraph(:cone, angle: 90, length: 18, duration: 2000, color: :purple)
        damage(40000, type: :magic)
      end

      ability :tentacle_slam, cooldown: 12_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :red)
        damage(35000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :genetic_bolt, cooldown: 5_000, target: :random do
        telegraph(:circle, radius: 4, duration: 1000, color: :purple)
        damage(22000, type: :magic)
      end

      ability :crushing_grip, cooldown: 15_000, target: :tank do
        damage(45000, type: :physical)
        debuff(:crushed, duration: 8000, stacks: 1)
      end

      ability :corruption_wave, cooldown: 18_000 do
        telegraph(:cone, angle: 120, length: 25, duration: 2500, color: :purple)
        damage(30000, type: :magic)
        debuff(:corrupted, duration: 10000, stacks: 1)
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase(:one)
      phase_emote("MY CHILDREN... DESTROY THEM!")
      enrage_modifier(1.2)

      ability :spawn_tentacles, cooldown: 30_000 do
        spawn(:add, creature_id: 60061, count: 4, spread: true)
      end

      ability :devour, cooldown: 45_000, target: :random do
        telegraph(:circle, radius: 6, duration: 3000, color: :red)
        debuff(:devoured, duration: 10000)
        coordination(:stack, min_players: 4, damage: 80000)
      end

      ability :tentacle_sweep, cooldown: 20_000 do
        telegraph(:line, width: 8, length: 40, duration: 2000, color: :red)
        damage(38000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :genetic_link, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :purple)
        coordination(:spread, min_distance: 8, damage: 40000)
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase(:two)
      phase_emote("FEEL THE STORM OF EVOLUTION!")
      enrage_modifier(1.4)

      ability :genetic_storm, cooldown: 35_000 do
        telegraph(:room_wide, duration: 5000)
        damage(45000, type: :magic)
        debuff(:storm_torn, duration: 15000, stacks: 1)
      end

      ability :phase_transition, cooldown: 60_000 do
        buff(:phased, duration: 8000)
        spawn(:wave, waves: 2, delay: 4000, creature_id: 60062, count_per_wave: 4)
      end

      ability :mass_tentacles, cooldown: 40_000 do
        spawn(:add, creature_id: 60061, count: 6, spread: true)
        telegraph(:room_wide, duration: 3000)
      end

      ability :genetic_nova, cooldown: 22_000 do
        telegraph(:circle, radius: 20, duration: 3000, color: :purple)
        damage(40000, type: :magic)
        movement(:knockback, distance: 12, source: :center)
      end

      ability :dread_pulse, cooldown: 15_000 do
        telegraph(:donut, inner_radius: 8, outer_radius: 25, duration: 2500, color: :purple)
        damage(35000, type: :magic)
      end
    end

    phase :four, health_below: 25 do
      inherit_phase(:three)
      phase_emote("EXTINCTION... IS... INEVITABLE!")
      enrage_modifier(1.6)

      ability :final_absorption, cooldown: 60_000 do
        buff(:absorbing, duration: 30000)
        buff(:damage_increase, duration: 30000)
        telegraph(:room_wide, duration: 5000)
      end

      ability :extinction_protocol, cooldown: 20_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :magic)
        debuff(:extinction, duration: 20000, stacks: 1)
      end

      ability :apocalypse_slam, cooldown: 12_000 do
        telegraph(:circle, radius: 20, duration: 2000, color: :red)
        damage(50000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :genetic_apocalypse, cooldown: 45_000 do
        telegraph(:room_wide, duration: 6000)
        damage(60000, type: :magic)
        spawn(:add, creature_id: 60063, count: 8, spread: true)
      end

      ability :consume_all, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(50000, type: :magic)
        buff(:consumed_power, duration: 20000)
      end
    end

    on_death do
      loot_table(60006)
      # Genetic Archives completion
      achievement(6901)
    end
  end
end
