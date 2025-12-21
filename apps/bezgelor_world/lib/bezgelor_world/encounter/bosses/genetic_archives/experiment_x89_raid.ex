defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.ExperimentX89Raid do
  @moduledoc """
  Experiment X-89 encounter - Genetic Archives (First Boss - 20-man Raid)

  A failed Eldan experiment gone horribly wrong. Features:
  - Corruption spread mechanic requiring cleansing
  - Small bomb phase with targeted explosions
  - Big Bomb requiring raid coordination
  - Final Mutation enrage with massive damage

  ## Strategy
  Phase 1 (100-75%): Spread corruption carriers, cleanse quickly
  Phase 2 (75-50%): Dodge small bombs, stack for healing
  Phase 3 (50-25%): Big Bomb carrier must run to safe zone
  Phase 4 (<25%): Burn before Strain Overload wipes raid

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Experiment X-89" do
    boss_id(60001)
    health(45_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(4)

    phase :one, health_above: 75 do
      phase_emote("EXPERIMENT... AWAKE... HUNGRY...")

      ability :corruption, cooldown: 8_000, target: :random do
        debuff(:corrupted, duration: 10000, stacks: 1)
        coordination(:spread, min_distance: 6, damage: 25000)
      end

      ability :repugnant_spew, cooldown: 15_000, target: :tank do
        telegraph(:cone, angle: 90, length: 20, duration: 2500, color: :green)
        damage(35000, type: :poison)
        debuff(:melting, duration: 8000, stacks: 2)
      end

      ability :oozing_strike, cooldown: 6_000, target: :tank do
        damage(25000, type: :physical)
        debuff(:armor_melt, duration: 6000, stacks: 1)
      end

      ability :strain_burst, cooldown: 12_000 do
        telegraph(:circle, radius: 15, duration: 2000, color: :green)
        damage(20000, type: :poison)
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase(:one)
      phase_emote("MORE... POWER... BOMBS...")
      enrage_modifier(1.15)

      ability :small_bombs, cooldown: 20_000 do
        telegraph(:circle, radius: 6, duration: 3000, color: :red)
        damage(30000, type: :fire)
        spawn(:add, creature_id: 60011, count: 5, spread: true)
      end

      ability :shattering_shockwave, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(25000, type: :physical)
        movement(:knockback, distance: 10, source: :center)
      end

      ability :mutagen_spray, cooldown: 18_000 do
        telegraph(:cone, angle: 60, length: 25, duration: 2000, color: :green)
        damage(28000, type: :poison)
        debuff(:mutating, duration: 12000, stacks: 1)
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase(:two)
      phase_emote("BIG... BOOM... COMING...")
      enrage_modifier(1.3)

      ability :big_bomb, cooldown: 45_000, target: :random do
        telegraph(:circle, radius: 30, duration: 8000, color: :red)
        damage(150_000, type: :fire)
        debuff(:big_bomb_carrier, duration: 8000)
        coordination(:spread, min_distance: 30, damage: 150_000)
      end

      ability :resurgence, cooldown: 60_000, interruptible: true do
        buff(:regenerating, duration: 10000)
        telegraph(:circle, radius: 10, duration: 5000, color: :green)
      end

      ability :cascade_corruption, cooldown: 30_000 do
        telegraph(:room_wide, duration: 3000)
        debuff(:corrupted, duration: 8000, stacks: 2)
        damage(20000, type: :poison)
      end
    end

    phase :four, health_below: 25 do
      inherit_phase(:three)
      phase_emote("STRAIN... OVERLOAD... EXTINCTION!")
      enrage_modifier(1.5)

      ability :strain_overload, cooldown: 30_000 do
        buff(:enraged, duration: 30000)
        telegraph(:room_wide, duration: 5000)
        damage(35000, type: :poison)
      end

      ability :final_mutation, cooldown: 60_000 do
        buff(:final_form, duration: 60000)
        spawn(:add, creature_id: 60012, count: 8, spread: true)
      end

      ability :extinction_pulse, cooldown: 15_000 do
        telegraph(:room_wide, duration: 4000)
        damage(40000, type: :poison)
        debuff(:extinction, duration: 10000, stacks: 1)
      end
    end

    on_death do
      loot_table(60001)
    end
  end
end
