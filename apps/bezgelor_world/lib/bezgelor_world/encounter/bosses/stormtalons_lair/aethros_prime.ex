defmodule BezgelorWorld.Encounter.Bosses.StormtalonsLair.AethrosPrime do
  @moduledoc """
  Aethros Prime encounter - Stormtalon's Lair (Prime Difficulty)

  Level 50 Prime version with enhanced mechanics:
  - Significantly increased health and damage
  - Additional mechanics and tighter timings
  - Veteran-only abilities active from start

  Data sources: client_data, scaled from normal
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Aethros" do
    boss_id 32703
    health 15_000_000
    level 50
    enrage_timer 360_000
    interrupt_armor 3

    # Phase 1: 100% - 60% health
    phase :one, health_above: 60 do
      phase_emote "The winds obey my command!"

      ability :gust_of_aethros, cooldown: 10_000, target: :farthest do
        telegraph :cone, angle: 60, length: 25, duration: 1800, color: :blue
        damage 25000, type: :magic
        movement :knockback, distance: 18
      end

      ability :torrent, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 35000, type: :magic
        debuff :drenched, duration: 12000, stacks: 2
      end

      ability :wind_slash, cooldown: 6_000, target: :tank do
        damage 22000, type: :magic
        debuff :armor_shred, duration: 8000, stacks: 1
      end

      # Prime-only ability from start
      ability :updraft, cooldown: 20_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :purple
        damage 20000, type: :magic
        movement :knockback, distance: 25, source: :center
      end
    end

    # Phase 2: 60% - 30% health - Cyclone Phase
    phase :two, health_between: {30, 60} do
      inherit_phase :one
      phase_emote "Witness the fury of the tempest!"

      ability :manifest_cyclone, cooldown: 20_000 do
        spawn :add, creature_id: 32704, count: 4, spread: true
        telegraph :circle, radius: 12, duration: 1200, color: :purple
      end

      ability :howling_winds, cooldown: 18_000 do
        telegraph :room_wide, duration: 3500
        damage 18000, type: :magic
        movement :pull, distance: 15, target: :boss
      end

      ability :air_burst, cooldown: 12_000, target: :healer do
        telegraph :circle, radius: 6, duration: 1500, color: :blue
        damage 30000, type: :magic
        coordination :spread, required_distance: 10, damage: 20000
      end

      # Prime-only: Wind prison
      ability :wind_prison, cooldown: 25_000, target: :random do
        debuff :imprisoned, duration: 5000
        damage 15000, type: :magic
        coordination :stack, min_players: 2, damage: 50000
      end
    end

    # Phase 3: Below 30% health - Enrage
    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "You will be scattered to the winds!"
      enrage_modifier 1.5
      attack_speed_modifier 1.3

      ability :hurricane, cooldown: 25_000 do
        telegraph :donut, inner_radius: 6, outer_radius: 25, duration: 3000
        damage 50000, type: :magic
        movement :knockback, distance: 25, source: :center
      end

      ability :wind_shear, cooldown: 8_000 do
        telegraph :line, width: 6, length: 35, duration: 1200, color: :red
        damage 40000, type: :magic
      end

      # Prime-only: Devastating combo
      ability :tempest_barrage, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 30000, type: :magic
        spawn :add, creature_id: 32704, count: 6, spread: true
      end
    end

    on_death do
      loot_table 32703
    end
  end
end
