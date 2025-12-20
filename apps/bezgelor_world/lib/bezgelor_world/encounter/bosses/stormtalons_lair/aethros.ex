defmodule BezgelorWorld.Encounter.Bosses.StormtalonsLair.Aethros do
  @moduledoc """
  Aethros encounter - Stormtalon's Lair (Second Boss)

  An air elemental bound to Stormtalon's domain. Features:
  - Wind-based knockback mechanics (Gust of Aethros)
  - Torrent water/wind damage
  - Cyclone spawns that must be avoided
  - Platform positioning required to avoid being knocked off

  ## Strategy
  Phase 1 (100-60%): Position against walls to avoid knockback deaths
  Phase 2 (60-30%): Avoid cyclones, stay stacked for healing
  Phase 3 (<30%): High damage phase, burn quickly

  Data sources: client_data
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Aethros" do
    boss_id(17166)
    health(450_000)
    level(20)
    enrage_timer(420_000)
    interrupt_armor(2)

    # Phase 1: 100% - 60% health
    phase :one, health_above: 60 do
      phase_emote("The winds obey my command!")

      ability :gust_of_aethros, cooldown: 12_000, target: :farthest do
        telegraph(:cone, angle: 60, length: 20, duration: 2000, color: :blue)
        damage(5000, type: :magic)
        movement(:knockback, distance: 15)
      end

      ability :torrent, cooldown: 18_000, target: :random do
        telegraph(:circle, radius: 6, duration: 2500, color: :red)
        damage(7000, type: :magic)
        debuff(:drenched, duration: 10000, stacks: 1)
      end

      ability :wind_slash, cooldown: 8_000, target: :tank do
        damage(4500, type: :magic)
      end
    end

    # Phase 2: 60% - 30% health - Cyclone Phase
    phase :two, health_between: {30, 60} do
      inherit_phase(:one)
      phase_emote("Witness the fury of the tempest!")

      ability :manifest_cyclone, cooldown: 25_000 do
        spawn(:add, creature_id: 17167, count: 3, spread: true)
        telegraph(:circle, radius: 10, duration: 1500, color: :purple)
      end

      ability :howling_winds, cooldown: 20_000 do
        telegraph(:room_wide, duration: 4000)
        damage(4000, type: :magic)
        movement(:pull, distance: 10, target: :boss)
      end

      ability :air_burst, cooldown: 15_000, target: :healer do
        telegraph(:circle, radius: 5, duration: 1800, color: :blue)
        damage(6000, type: :magic)
        coordination(:spread, required_distance: 8, damage: 4000)
      end
    end

    # Phase 3: Below 30% health - Enrage
    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("You will be scattered to the winds!")
      enrage_modifier(1.4)
      attack_speed_modifier(1.2)

      ability :hurricane, cooldown: 30_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 20, duration: 3500)
        damage(12000, type: :magic)
        movement(:knockback, distance: 20, source: :center)
      end

      ability :wind_shear, cooldown: 10_000 do
        telegraph(:line, width: 5, length: 30, duration: 1500, color: :red)
        damage(8000, type: :magic)
      end
    end

    on_death do
      loot_table(17166)
    end
  end
end
