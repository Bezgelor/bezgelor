defmodule BezgelorWorld.Encounter.Bosses.VeteranSkullcano.StewShamanTuggaVeteran do
  @moduledoc """
  Stew-Shaman Tugga (Veteran) encounter - Veteran Skullcano (First Boss)

  The veteran version of Tugga with enhanced cooking mechanics. Features:
  - Higher damage and more adds
  - Toxic Stew room-wide poison damage
  - Helper Horde waves in phase 2

  ## Strategy
  Phase 1 (100-50%): Kill ingredient adds, avoid Boiling Splash
  Phase 2 (<50%): Survive Toxic Stew, handle Helper Horde waves

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stew-Shaman Tugga (Veteran)" do
    boss_id(50701)
    health(3_500_000)
    level(50)
    enrage_timer(480_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("Time to make the ULTIMATE stew!")

      ability :boiling_splash, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :red)
        damage(14000, type: :fire)
        debuff(:scalded, duration: 8000, stacks: 1)
      end

      ability :stew_ladle, cooldown: 8_000, target: :tank do
        damage(18000, type: :physical)
        debuff(:battered, duration: 10000, stacks: 1)
      end

      ability :summon_ingredients, cooldown: 25_000 do
        spawn(:add, creature_id: 50712, count: 3, spread: true)
      end

      ability :spice_bomb, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :red)
        damage(12000, type: :fire)
      end

      ability :taste_test, cooldown: 18_000 do
        telegraph(:cone, angle: 60, length: 20, duration: 2000, color: :green)
        damage(10000, type: :poison)
        debuff(:nauseous, duration: 6000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("Secret ingredient time!")
      enrage_modifier(1.4)

      ability :toxic_stew, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(12000, type: :poison)
        debuff(:poisoned, duration: 12000, stacks: 2)
      end

      ability :explosive_recipe, cooldown: 22_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :red)
        damage(18000, type: :fire)
        movement(:knockback, distance: 10)
      end

      ability :helper_horde, cooldown: 30_000 do
        spawn(:wave, waves: 2, delay: 4000, creature_id: 50712, count_per_wave: 3)
      end

      ability :cauldron_overflow, cooldown: 25_000 do
        telegraph(:circle, radius: 20, duration: 3000, color: :green)
        damage(14000, type: :poison)
      end

      ability :final_recipe, cooldown: 40_000 do
        buff(:cooking_frenzy, duration: 12000)
        buff(:damage_increase, duration: 12000)
        spawn(:add, creature_id: 50712, count: 4, spread: true)
      end
    end

    on_death do
      loot_table(50701)
    end
  end
end
