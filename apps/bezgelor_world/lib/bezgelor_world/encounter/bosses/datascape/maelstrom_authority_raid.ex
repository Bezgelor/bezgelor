defmodule BezgelorWorld.Encounter.Bosses.Datascape.MaelstromAuthorityRaid do
  @moduledoc """
  Maelstrom Authority encounter - Datascape (Third Boss - 40-man Raid)

  A being of pure elemental storm energy controlling weather within the Datascape. Features:
  - Chain Lightning spread mechanic
  - Wind Wall knockback requiring positioning
  - Tornado hazards spawning throughout arena
  - Eye of the Storm donut mechanic

  ## Strategy
  Phase 1 (100-70%): Spread for Chain Lightning, position for Wind Wall
  Phase 2 (70-40%): Navigate tornadoes, stand in Eye of Storm safe zone
  Phase 3 (<40%): Survive Category Five, burn through Perfect Storm

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Maelstrom Authority" do
    boss_id 70003
    health 160_000_000
    level 50
    enrage_timer 1020_000
    interrupt_armor 8

    phase :one, health_above: 70 do
      phase_emote "THE STORM ANSWERS TO ME!"

      ability :lightning_conduit, cooldown: 10_000, target: :tank do
        damage 75000, type: :magic
        debuff :conductivity, duration: 12000, stacks: 1
      end

      ability :storm_surge, cooldown: 14_000, target: :random do
        telegraph :circle, radius: 15, duration: 2000, color: :blue
        damage 50000, type: :magic
        debuff :storm_touched, duration: 10000, stacks: 1
      end

      ability :chain_lightning, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 5, duration: 2500, color: :blue
        coordination :spread, min_distance: 8, damage: 60000
      end

      ability :wind_wall, cooldown: 25_000 do
        telegraph :line, width: 10, length: 60, duration: 3000, color: :blue
        damage 55000, type: :magic
        movement :knockback, distance: 20
      end

      ability :static_shock, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1500, color: :blue
        damage 40000, type: :magic
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase :one
      phase_emote "FEEL THE TEMPEST'S WRATH!"
      enrage_modifier 1.3

      ability :tornado, cooldown: 35_000 do
        spawn :add, creature_id: 70032, count: 3, spread: true
        telegraph :circle, radius: 8, duration: 2000, color: :blue
      end

      ability :eye_of_the_storm, cooldown: 40_000 do
        telegraph :donut, inner_radius: 10, outer_radius: 30, duration: 4000, color: :blue
        damage 80000, type: :magic
      end

      ability :static_field, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :blue
        debuff :static, duration: 12000, stacks: 5
        damage 35000, type: :magic
      end

      ability :gale_force, cooldown: 22_000 do
        telegraph :cone, angle: 90, length: 35, duration: 2500, color: :blue
        damage 50000, type: :magic
        movement :knockback, distance: 15
      end

      ability :thunderstrike, cooldown: 30_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :blue
        damage 65000, type: :magic
        coordination :spread, min_distance: 10, damage: 45000
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "BECOME ONE WITH THE MAELSTROM!"
      enrage_modifier 1.6

      ability :category_five, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 70000, type: :magic
        debuff :storm_battered, duration: 15000, stacks: 2
      end

      ability :supercell, cooldown: 45_000 do
        telegraph :circle, radius: 25, duration: 4000, color: :blue
        damage 90000, type: :magic
        movement :pull, distance: 15
      end

      ability :perfect_storm, cooldown: 60_000 do
        telegraph :room_wide, duration: 6000
        damage 100000, type: :magic
      end

      ability :lightning_apocalypse, cooldown: 28_000 do
        telegraph :cross, length: 45, width: 8, duration: 3000, color: :blue
        damage 75000, type: :magic
      end

      ability :storm_avatar, cooldown: 50_000 do
        buff :storm_empowered, duration: 20000
        buff :damage_increase, duration: 20000
        spawn :add, creature_id: 70032, count: 5, spread: true
      end
    end

    on_death do
      loot_table 70003
      achievement 7003  # Datascape: Maelstrom Authority
    end
  end
end
