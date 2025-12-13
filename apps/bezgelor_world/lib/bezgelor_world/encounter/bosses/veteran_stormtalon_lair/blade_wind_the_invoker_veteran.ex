defmodule BezgelorWorld.Encounter.Bosses.VeteranStormtalonLair.BladeWindTheInvokerVeteran do
  @moduledoc """
  Blade-Wind the Invoker (Veteran) encounter - Veteran Stormtalon's Lair (Second Boss)

  The veteran version of Blade-Wind with enhanced mechanics. Features:
  - 3-phase fight with increasing damage
  - Wind Elemental adds throughout
  - Cutting Winds cross pattern
  - Storm Nova room-wide in final phase

  ## Strategy
  Phase 1 (100-70%): Avoid Wind Blade lines, dodge Cutting Winds cross
  Phase 2 (70-40%): Kill Elementals quickly, watch for Tornado pull
  Phase 3 (<40%): Survive Storm Nova, burn through Blade Storm

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Blade-Wind the Invoker (Veteran)" do
    boss_id 50502
    health 4_000_000
    level 50
    enrage_timer 540_000
    interrupt_armor 4

    phase :one, health_above: 70 do
      phase_emote "The blade winds answer my call!"

      ability :blade_fury, cooldown: 10_000, target: :tank do
        damage 20000, type: :physical
        debuff :blade_wound, duration: 10000, stacks: 1
      end

      ability :wind_blade, cooldown: 12_000 do
        telegraph :line, width: 5, length: 35, duration: 2000, color: :blue
        damage 15000, type: :magic
      end

      ability :invoke_storm, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 10000, type: :magic
        debuff :invoked, duration: 8000, stacks: 1
      end

      ability :cutting_winds, cooldown: 18_000 do
        telegraph :cross, length: 30, width: 5, duration: 2500, color: :blue
        damage 13000, type: :magic
      end

      ability :air_slash, cooldown: 8_000, target: :random do
        telegraph :cone, angle: 45, length: 20, duration: 1500, color: :blue
        damage 11000, type: :magic
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase :one
      phase_emote "I summon the spirits of wind!"
      enrage_modifier 1.35

      ability :summon_elementals, cooldown: 30_000 do
        spawn :add, creature_id: 50522, count: 2, spread: true
      end

      ability :tornado, cooldown: 20_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :blue
        damage 14000, type: :magic
        movement :pull, distance: 10
      end

      ability :empowered_blades, cooldown: 35_000 do
        buff :empowered, duration: 10000
        buff :damage_increase, duration: 10000
      end

      ability :wind_wall, cooldown: 22_000 do
        telegraph :line, width: 8, length: 40, duration: 2000, color: :blue
        damage 12000, type: :magic
        movement :knockback, distance: 12
      end

      ability :blade_dance, cooldown: 28_000 do
        telegraph :circle, radius: 15, duration: 3000, color: :blue
        damage 13000, type: :magic
        spawn :add, creature_id: 50522, count: 1, spread: true
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "THE FULL FURY OF THE STORM!"
      enrage_modifier 1.6

      ability :storm_nova, cooldown: 30_000 do
        telegraph :room_wide, duration: 4500
        damage 16000, type: :magic
        debuff :storm_battered, duration: 15000, stacks: 1
      end

      ability :blade_storm, cooldown: 25_000 do
        telegraph :circle, radius: 20, duration: 3500, color: :blue
        damage 18000, type: :magic
      end

      ability :final_invocation, cooldown: 40_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 50522, count_per_wave: 2
        telegraph :room_wide, duration: 2000
        damage 8000, type: :magic
      end

      ability :wind_mastery, cooldown: 45_000 do
        buff :wind_master, duration: 15000
        buff :damage_increase, duration: 15000
        telegraph :circle, radius: 10, duration: 2000, color: :blue
        damage 10000, type: :magic
      end
    end

    on_death do
      loot_table 50502
    end
  end
end
