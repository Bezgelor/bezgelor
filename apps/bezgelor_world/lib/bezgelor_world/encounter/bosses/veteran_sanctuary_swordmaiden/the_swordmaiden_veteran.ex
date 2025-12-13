defmodule BezgelorWorld.Encounter.Bosses.VeteranSanctuarySwordmaiden.TheSwordmaidenVeteran do
  @moduledoc """
  The Swordmaiden (Veteran) - Veteran Sanctuary of the Swordmaiden (Final Boss)

  Enhanced 4-phase blade combat encounter.
  """

  use BezgelorWorld.Encounter.DSL

  boss "The Swordmaiden (Veteran)" do
    boss_id 50805
    health 6_000_000
    level 50
    enrage_timer 660_000
    interrupt_armor 5

    phase :one, health_above: 75 do
      phase_emote "My blade shall judge you!"

      ability :blade_strike, cooldown: 8_000, target: :tank do
        damage 28000, type: :physical
        debuff :bleeding, duration: 12000, stacks: 1
      end

      ability :whirlwind, cooldown: 12_000 do
        telegraph :circle, radius: 12, duration: 2000, color: :red
        damage 18000, type: :physical
      end

      ability :blade_throw, cooldown: 15_000, target: :random do
        telegraph :line, width: 5, length: 35, duration: 2000, color: :red
        damage 16000, type: :physical
      end

      ability :summon_blades, cooldown: 25_000 do
        spawn :add, creature_id: 50852, count: 2, spread: true
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase :one
      phase_emote "Face my TRUE power!"
      enrage_modifier 1.3

      ability :blade_storm, cooldown: 28_000 do
        telegraph :room_wide, duration: 4000
        damage 16000, type: :physical
        debuff :storm_cut, duration: 10000, stacks: 1
      end

      ability :cross_slash, cooldown: 18_000 do
        telegraph :cross, length: 30, width: 6, duration: 2500, color: :red
        damage 20000, type: :physical
      end

      ability :blade_dance, cooldown: 22_000 do
        buff :dancing, duration: 8000
        telegraph :circle, radius: 15, duration: 2000, color: :red
        damage 14000, type: :physical
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase :two
      phase_emote "My blades HUNGER!"
      enrage_modifier 1.5

      ability :mass_blades, cooldown: 30_000 do
        spawn :add, creature_id: 50852, count: 4, spread: true
        telegraph :room_wide, duration: 2000
        damage 10000, type: :physical
      end

      ability :execution, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 8, duration: 3000, color: :red
        damage 24000, type: :physical
      end

      ability :blade_barrier, cooldown: 35_000 do
        buff :blade_barrier, duration: 12000
        buff :damage_reduction, duration: 12000
      end
    end

    phase :four, health_below: 25 do
      inherit_phase :three
      phase_emote "FEEL THE MAIDEN'S WRATH!"
      enrage_modifier 1.8

      ability :apocalypse_blade, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 24000, type: :physical
        debuff :doomed, duration: 20000, stacks: 2
      end

      ability :final_judgment, cooldown: 40_000, target: :random do
        telegraph :circle, radius: 10, duration: 4000, color: :red
        coordination :stack, min_players: 5, damage: 80000
      end

      ability :sword_mastery, cooldown: 50_000 do
        buff :sword_master, duration: 20000
        buff :damage_increase, duration: 20000
        spawn :add, creature_id: 50852, count: 3, spread: true
      end
    end

    on_death do
      loot_table 50805
      achievement 5080  # Veteran Sanctuary completion
    end
  end
end
