defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.GeneticMonstrosityRaid do
  @moduledoc """
  Genetic Monstrosity encounter - Genetic Archives (Fourth Boss - 20-man Raid)

  A massive abomination with multiple mutation stacks. Features:
  - Mutation stacks requiring tank swaps
  - Monstrous Cleave frontal damage
  - Add waves that heal the boss if alive
  - Final Mutation enrage transformation

  ## Strategy
  Phase 1 (100-70%): Tank swap at 3 Mutation stacks
  Phase 2 (70-30%): Kill adds quickly, they heal boss
  Phase 3 (<30%): Burn through Final Mutation before wipe

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Genetic Monstrosity" do
    boss_id(60004)
    health(55_000_000)
    level(50)
    enrage_timer(660_000)
    interrupt_armor(4)

    phase :one, health_above: 70 do
      phase_emote("*ROARS* FLESH... CONSUME... GROW!")

      ability :genetic_mutation, cooldown: 15_000, target: :tank do
        debuff(:mutated, duration: 30000, stacks: 1)
        damage(25000, type: :magic)
      end

      ability :monstrous_cleave, cooldown: 8_000 do
        telegraph(:cone, angle: 120, length: 20, duration: 2000, color: :red)
        damage(40000, type: :physical)
      end

      ability :hulking_slam, cooldown: 12_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :red)
        damage(35000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :rend, cooldown: 6_000, target: :tank do
        damage(30000, type: :physical)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end
    end

    phase :two, health_between: {30, 70} do
      inherit_phase(:one)
      phase_emote("MORE FLESH! MORE POWER!")
      enrage_modifier(1.25)

      ability :hulking_smash, cooldown: 12_000 do
        telegraph(:circle, radius: 18, duration: 2000, color: :red)
        damage(38000, type: :physical)
        movement(:knockback, distance: 10, source: :center)
      end

      ability :spawn_mutants, cooldown: 30_000 do
        spawn(:wave, waves: 2, delay: 5000, creature_id: 60041, count_per_wave: 3)
      end

      ability :absorb, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 8, duration: 3000, color: :purple)
        damage(30000, type: :magic)
        buff(:absorbed_power, duration: 15000)
      end

      ability :mutation_burst, cooldown: 20_000 do
        telegraph(:room_wide, duration: 3000)
        damage(25000, type: :magic)
        debuff(:mutating, duration: 10000, stacks: 1)
      end

      ability :ground_pound, cooldown: 18_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 25, duration: 2500, color: :red)
        damage(35000, type: :physical)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("ULTIMATE FORM! UNSTOPPABLE!")
      enrage_modifier(1.5)

      ability :genetic_overload, cooldown: 20_000 do
        telegraph(:room_wide, duration: 4000)
        damage(45000, type: :magic)
        debuff(:overloaded, duration: 15000, stacks: 1)
      end

      ability :final_mutation, cooldown: 60_000 do
        buff(:final_form, duration: 60000)
        buff(:damage_increase, duration: 60000)
        buff(:size_increase, duration: 60000)
      end

      ability :devour, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 6, duration: 2000, color: :red)
        damage(50000, type: :physical)
        buff(:devoured_power, duration: 10000)
      end

      ability :extinction_slam, cooldown: 25_000 do
        telegraph(:room_wide, duration: 5000)
        damage(50000, type: :physical)
        movement(:knockback, distance: 15, source: :center)
      end
    end

    on_death do
      loot_table(60004)
    end
  end
end
