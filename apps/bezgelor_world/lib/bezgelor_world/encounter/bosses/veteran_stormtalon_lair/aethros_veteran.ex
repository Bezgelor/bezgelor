defmodule BezgelorWorld.Encounter.Bosses.VeteranStormtalonLair.AethrosVeteran do
  @moduledoc """
  Aethros (Veteran) encounter - Veteran Stormtalon's Lair (First Boss)

  The veteran version of Aethros with enhanced mechanics. Features:
  - Higher damage and health
  - Chain Lightning spread mechanic
  - Cyclone adds that must be killed
  - Eye of the Storm donut mechanic

  ## Strategy
  Phase 1 (100-60%): Avoid Tempest circles, don't stand in Cyclone
  Phase 2 (<60%): Spread for Chain Lightning, stand in Eye of Storm safe zone

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Aethros (Veteran)" do
    boss_id 50501
    health 3_500_000
    level 50
    enrage_timer 480_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "The winds of destruction are at my command!"

      ability :lightning_strike, cooldown: 8_000, target: :tank do
        damage 18000, type: :magic
        debuff :shocked, duration: 8000, stacks: 1
      end

      ability :tempest, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :blue
        damage 12000, type: :magic
      end

      ability :cyclone, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2500, color: :blue
        damage 10000, type: :magic
        movement :pull, distance: 8
      end

      ability :wind_slash, cooldown: 10_000 do
        telegraph :cone, angle: 60, length: 25, duration: 2000, color: :blue
        damage 14000, type: :magic
      end

      ability :gust, cooldown: 18_000 do
        telegraph :line, width: 6, length: 30, duration: 1800, color: :blue
        damage 10000, type: :magic
        movement :knockback, distance: 10
      end
    end

    phase :two, health_below: 60 do
      inherit_phase :one
      phase_emote "Feel the fury of the storm!"
      enrage_modifier 1.4

      ability :eye_of_the_storm, cooldown: 25_000 do
        telegraph :donut, inner_radius: 8, outer_radius: 20, duration: 3500, color: :blue
        damage 16000, type: :magic
      end

      ability :chain_lightning, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 5, duration: 3000, color: :blue
        coordination :spread, min_distance: 8, damage: 14000
      end

      ability :spawn_cyclones, cooldown: 30_000 do
        spawn :add, creature_id: 50512, count: 3, spread: true
      end

      ability :storm_fury, cooldown: 35_000 do
        telegraph :room_wide, duration: 4000
        damage 14000, type: :magic
        debuff :storm_touched, duration: 12000, stacks: 1
      end

      ability :empowered_winds, cooldown: 40_000 do
        buff :wind_empowered, duration: 12000
        buff :damage_increase, duration: 12000
      end
    end

    on_death do
      loot_table 50501
    end
  end
end
