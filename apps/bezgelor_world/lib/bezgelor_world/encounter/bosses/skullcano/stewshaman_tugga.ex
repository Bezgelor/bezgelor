defmodule BezgelorWorld.Encounter.Bosses.Skullcano.StewshamanTugga do
  @moduledoc """
  Stew-Shaman Tugga encounter - Skullcano (First Boss)

  A crazed Lopp cook who uses his bubbling cauldron to create chaos. Features:
  - Cauldron-based cooking attacks with various debuffs
  - Ingredient toss targeting random players
  - Lopp helper adds that buff the boss
  - Explosive finale when cauldron overheats

  ## Strategy
  Phase 1 (100-50%): Dodge ingredient tosses, interrupt Stir the Pot
  Phase 2 (<50%): Kill helpers quickly, spread for Toxic Stew, avoid cauldron

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stew-Shaman Tugga" do
    boss_id 50201
    health 1_500_000
    level 30
    enrage_timer 480_000
    interrupt_armor 2

    # Phase 1: 100% - 50% health - Cooking Phase
    phase :one, health_above: 50 do
      phase_emote "Time to make the stew! You be the ingredients!"

      ability :boiling_splash, cooldown: 8_000 do
        telegraph :circle, radius: 8, duration: 1500, color: :red
        damage 5000, type: :fire
        debuff :scalded, duration: 6000, stacks: 1
      end

      ability :throw_ingredient, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 5, duration: 1200, color: :red
        damage 4000, type: :physical
        debuff :sauced, duration: 4000, stacks: 1
      end

      ability :stir_the_pot, cooldown: 15_000, interruptible: true do
        buff :stirring, duration: 5000
        telegraph :circle, radius: 6, duration: 3000, color: :purple
      end

      ability :seasoning_toss, cooldown: 10_000, target: :random do
        telegraph :cone, angle: 45, length: 15, duration: 1200, color: :red
        damage 3500, type: :fire
        debuff :blinded, duration: 3000
      end
    end

    # Phase 2: Below 50% health - Overheating
    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "Stew is getting SPICY! MORE HEAT!"
      enrage_modifier 1.2

      ability :toxic_stew, cooldown: 20_000 do
        telegraph :room_wide, duration: 3000
        damage 6000, type: :poison
        debuff :poisoned, duration: 10000, stacks: 2
      end

      ability :call_helpers, cooldown: 30_000 do
        spawn :add, creature_id: 50211, count: 2, spread: true
        phase_emote "Helpers! Get in the kitchen!"
      end

      ability :explosive_cauldron, cooldown: 25_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :red
        damage 8000, type: :fire
        movement :knockback, distance: 10
      end

      ability :taste_test, cooldown: 18_000, target: :tank do
        damage 7000, type: :physical
        debuff :weakened, duration: 8000, stacks: 1
      end

      ability :super_seasoning, cooldown: 35_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :red
        damage 5000, type: :fire
        spawn :add, creature_id: 50212, count: 3, spread: true
      end
    end

    on_death do
      loot_table 50201
    end
  end
end
