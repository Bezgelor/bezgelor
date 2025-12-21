defmodule BezgelorWorld.Encounter.Bosses.UltimateProtogames.MalgraveMauler do
  @moduledoc """
  Malgrave Mauler encounter - Ultimate Protogames (Final Boss)

  The ultimate champion of the Protogames, themed after the Malgrave desert. Features:
  - Desert/sand themed mechanics
  - Quicksand slowing debuff
  - Scorpion add spawns
  - Sandstorm donut mechanic in final phase

  ## Strategy
  Phase 1 (100-70%): Avoid Quicksand, dodge Sand Blast
  Phase 2 (70-40%): Kill Scorpions quickly, heal through Heat Wave
  Phase 3 (<40%): Position for Sandstorm donut, burn through Malgrave Madness

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Malgrave Mauler" do
    boss_id(50404)
    health(3_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(4)

    phase :one, health_above: 70 do
      phase_emote("WELCOME TO THE ULTIMATE CHALLENGE!")

      ability :mauling_strike, cooldown: 8_000, target: :tank do
        damage(15000, type: :physical)
        debuff(:mauled, duration: 10000, stacks: 1)
      end

      ability :desert_storm, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 12, duration: 2000, color: :brown)
        damage(9000, type: :physical)
      end

      ability :sand_blast, cooldown: 12_000 do
        telegraph(:cone, angle: 60, length: 25, duration: 2000, color: :brown)
        damage(10000, type: :physical)
        debuff(:blinded, duration: 3000)
      end

      ability :quicksand, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 8, duration: 2500, color: :brown)
        damage(6000, type: :physical)
        debuff(:slowed, duration: 4000)
      end

      ability :dust_devil, cooldown: 18_000 do
        telegraph(:circle, radius: 6, duration: 1500, color: :brown)
        damage(7000, type: :physical)
        movement(:pull, distance: 5)
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase(:one)
      phase_emote("LET'S TURN UP THE HEAT!")
      enrage_modifier(1.3)

      ability :heat_wave, cooldown: 25_000 do
        telegraph(:room_wide, duration: 3500)
        damage(8000, type: :fire)
        debuff(:overheated, duration: 10000, stacks: 1)
      end

      ability :summon_scorpions, cooldown: 30_000 do
        spawn(:add, creature_id: 50442, count: 3, spread: true)
      end

      ability :scorching_slam, cooldown: 20_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :red)
        damage(12000, type: :fire)
        movement(:knockback, distance: 10)
      end

      ability :mirage, cooldown: 35_000 do
        buff(:mirage, duration: 8000)
        spawn(:add, creature_id: 50443, count: 2, spread: true)
      end

      ability :burning_sand, cooldown: 22_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :red)
        damage(10000, type: :fire)
        debuff(:burning, duration: 6000, stacks: 1)
      end
    end

    phase :three, health_below: 40 do
      inherit_phase(:two)
      phase_emote("TIME FOR THE GRAND FINALE!")
      enrage_modifier(1.5)

      ability :malgrave_madness, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(12000, type: :physical)
        debuff(:maddened, duration: 12000, stacks: 1)
      end

      ability :sandstorm, cooldown: 25_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 20, duration: 3500, color: :brown)
        damage(14000, type: :physical)
      end

      ability :final_mauling, cooldown: 18_000 do
        telegraph(:cone, angle: 120, length: 20, duration: 2500, color: :red)
        damage(16000, type: :physical)
      end

      ability :desert_wrath, cooldown: 35_000 do
        telegraph(:cross, length: 30, width: 8, duration: 3000, color: :brown)
        damage(13000, type: :physical)
        spawn(:add, creature_id: 50442, count: 2, spread: true)
      end

      ability :ultimate_challenge, cooldown: 50_000 do
        buff(:ultimate_form, duration: 15000)
        buff(:damage_increase, duration: 15000)
        telegraph(:room_wide, duration: 2000)
        damage(10000, type: :physical)
      end
    end

    on_death do
      loot_table(50404)
      # Ultimate Protogames completion
      achievement(5040)
    end
  end
end
