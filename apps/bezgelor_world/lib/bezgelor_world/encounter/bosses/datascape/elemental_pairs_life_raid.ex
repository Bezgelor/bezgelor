defmodule BezgelorWorld.Encounter.Bosses.Datascape.ElementalPairsLifeRaid do
  @moduledoc """
  Elemental Pairs: Life encounter - Datascape (Sixth Boss - 40-man Raid)

  One of four elemental pairs that must be killed within 20 seconds of each other.
  Life element features nature damage and healing/regeneration mechanics. Features:
  - Entangle root mechanic requiring dispels
  - Photosynthesis self-heal buff that must be interrupted
  - Lasher adds that multiply if not killed quickly
  - Overgrowth room-wide damage

  ## Strategy
  Phase 1 (100-50%): Interrupt Photosynthesis, dispel Entangle
  Phase 2 (<50%): Kill Lashers before they multiply, burn through Overgrowth
  IMPORTANT: Must kill within 20 seconds of Earth element or both heal to full

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Elemental Pairs - Life" do
    boss_id 70006
    health 100_000_000
    level 50
    enrage_timer 720_000
    interrupt_armor 5

    phase :one, health_above: 50 do
      phase_emote "LIFE FINDS A WAY!"

      ability :vine_lash, cooldown: 10_000, target: :tank do
        damage 60000, type: :nature
        debuff :vine_wrapped, duration: 8000, stacks: 1
      end

      ability :entangle, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :green
        damage 40000, type: :nature
        debuff :rooted, duration: 4000
      end

      ability :photosynthesis, cooldown: 30_000, interruptible: true do
        buff :regenerating, duration: 10000
        telegraph :circle, radius: 15, duration: 3000, color: :green
      end

      ability :seed_burst, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :green
        damage 35000, type: :nature
        spawn :add, creature_id: 70062, count: 2, spread: true
      end

      ability :thorn_volley, cooldown: 12_000 do
        telegraph :cone, angle: 60, length: 25, duration: 2000, color: :green
        damage 45000, type: :nature
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "GROWTH CANNOT BE STOPPED!"
      enrage_modifier 1.4

      ability :overgrowth, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 50000, type: :nature
        debuff :overgrown, duration: 10000, stacks: 1
      end

      ability :spawn_lashers, cooldown: 35_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 70062, count_per_wave: 3
      end

      ability :natures_wrath, cooldown: 40_000 do
        telegraph :circle, radius: 25, duration: 4000, color: :green
        damage 70000, type: :nature
      end

      ability :root_network, cooldown: 22_000 do
        telegraph :cross, length: 35, width: 6, duration: 2500, color: :green
        damage 50000, type: :nature
        debuff :rooted, duration: 3000
      end

      ability :bloom, cooldown: 28_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :green
        damage 55000, type: :nature
        buff :blooming, duration: 8000
      end

      ability :wild_growth, cooldown: 45_000 do
        buff :wild_energy, duration: 15000
        buff :damage_increase, duration: 15000
        spawn :add, creature_id: 70062, count: 4, spread: true
      end
    end

    on_death do
      loot_table 70006
    end
  end
end
