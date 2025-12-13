defmodule BezgelorWorld.Encounter.Bosses.Datascape.ElementalPairsFireRaid do
  @moduledoc """
  Elemental Pairs: Fire encounter - Datascape (Eighth Boss - 40-man Raid)

  One of four elemental pairs that must be killed within 20 seconds of each other.
  Fire element features intense fire damage and burning mechanics. Features:
  - Heat Wave stacking burning debuff
  - Inferno ground effects
  - Ember adds that explode on death
  - Firestorm room-wide requiring healing cooldowns

  ## Strategy
  Phase 1 (100-50%): Manage Heat Wave stacks, avoid Inferno puddles
  Phase 2 (<50%): Kill Embers away from raid, survive Conflagration
  IMPORTANT: Must kill within 20 seconds of Logic element or both heal to full

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Elemental Pairs - Fire" do
    boss_id 70008
    health 100_000_000
    level 50
    enrage_timer 720_000
    interrupt_armor 5

    phase :one, health_above: 50 do
      phase_emote "BURN IN ETERNAL FLAMES!"

      ability :flame_strike, cooldown: 10_000, target: :tank do
        damage 70000, type: :fire
        debuff :scorched, duration: 10000, stacks: 1
      end

      ability :inferno, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :red
        damage 50000, type: :fire
        debuff :burning_ground, duration: 8000
      end

      ability :pyroblast, cooldown: 18_000 do
        telegraph :line, width: 6, length: 40, duration: 2500, color: :red
        damage 55000, type: :fire
      end

      ability :heat_wave, cooldown: 20_000, target: :random do
        telegraph :cone, angle: 90, length: 30, duration: 2000, color: :red
        debuff :burning, duration: 8000, stacks: 3
        damage 40000, type: :fire
      end

      ability :fire_bolt, cooldown: 8_000, target: :random do
        telegraph :circle, radius: 5, duration: 1200, color: :red
        damage 35000, type: :fire
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "THE FLAMES CONSUME ALL!"
      enrage_modifier 1.4

      ability :firestorm, cooldown: 30_000 do
        telegraph :room_wide, duration: 5000
        damage 55000, type: :fire
        debuff :fire_touched, duration: 12000, stacks: 1
      end

      ability :spawn_embers, cooldown: 35_000 do
        spawn :add, creature_id: 70082, count: 6, spread: true
      end

      ability :conflagration, cooldown: 40_000 do
        telegraph :circle, radius: 20, duration: 4000, color: :red
        damage 75000, type: :fire
      end

      ability :flame_pillar, cooldown: 22_000 do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 60000, type: :fire
        movement :knockback, distance: 10
      end

      ability :blazing_path, cooldown: 25_000 do
        telegraph :line, width: 10, length: 45, duration: 3000, color: :red
        damage 65000, type: :fire
        debuff :burning, duration: 10000, stacks: 2
      end

      ability :molten_fury, cooldown: 45_000 do
        buff :molten_form, duration: 15000
        buff :damage_increase, duration: 15000
        telegraph :circle, radius: 15, duration: 2000, color: :red
        damage 50000, type: :fire
      end
    end

    on_death do
      loot_table 70008
    end
  end
end
