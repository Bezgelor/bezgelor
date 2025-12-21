defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.PhagebornConvergenceRaid do
  @moduledoc """
  Phageborn Convergence encounter - Genetic Archives (Fifth Boss - 20-man Raid)

  Multiple phageborn creatures that converge into one. Features:
  - Multiple targets that share damage
  - Convergence mechanic requiring balanced DPS
  - Phageborn Eruption room-wide AoE
  - Final convergence enrage

  ## Strategy
  Phase 1 (100-60%): Balance damage between all convergence targets
  Phase 2 (<60%): Handle Convergence stacks, burst during vulnerability

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Phageborn Convergence" do
    boss_id(60005)
    health(48_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("WE ARE MANY... WE ARE ONE...")

      ability :converging_strike, cooldown: 10_000, target: :tank do
        damage(35000, type: :physical)
        debuff(:converging, duration: 8000, stacks: 1)
      end

      ability :phage_bolt, cooldown: 6_000, target: :random do
        telegraph(:circle, radius: 5, duration: 1200, color: :purple)
        damage(20000, type: :magic)
      end

      ability :split_attack, cooldown: 15_000 do
        telegraph(:cross, length: 25, width: 5, duration: 2000, color: :purple)
        damage(30000, type: :magic)
      end

      ability :phage_spray, cooldown: 12_000 do
        telegraph(:cone, angle: 60, length: 20, duration: 2000, color: :purple)
        damage(28000, type: :magic)
        debuff(:phage_infected, duration: 10000, stacks: 1)
      end

      ability :summon_fragment, cooldown: 25_000 do
        spawn(:add, creature_id: 60051, count: 2, spread: true)
      end
    end

    phase :two, health_below: 60 do
      inherit_phase(:one)
      phase_emote("CONVERGING... BECOMING WHOLE...")
      enrage_modifier(1.35)

      ability :convergence, cooldown: 40_000 do
        buff(:converging, duration: 15000)
        telegraph(:room_wide, duration: 5000)
        spawn(:add, creature_id: 60052, count: 4, spread: true)
      end

      ability :phageborn_eruption, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(40000, type: :magic)
        debuff(:erupted, duration: 12000, stacks: 1)
      end

      ability :mass_infection, cooldown: 30_000 do
        telegraph(:circle, radius: 20, duration: 3000, color: :purple)
        debuff(:phage_infected, duration: 15000, stacks: 2)
        damage(25000, type: :magic)
      end

      ability :unity_pulse, cooldown: 18_000 do
        telegraph(:circle, radius: 15, duration: 2000, color: :purple)
        damage(32000, type: :magic)
        movement(:pull, distance: 10)
      end

      ability :fragment_explosion, cooldown: 35_000 do
        telegraph(:circle, radius: 12, duration: 2500, color: :red)
        damage(45000, type: :fire)
        spawn(:add, creature_id: 60051, count: 3, spread: true)
      end

      ability :final_convergence, cooldown: 60_000 do
        buff(:fully_converged, duration: 20000)
        buff(:damage_increase, duration: 20000)
        telegraph(:room_wide, duration: 6000)
        damage(50000, type: :magic)
      end
    end

    on_death do
      loot_table(60005)
    end
  end
end
