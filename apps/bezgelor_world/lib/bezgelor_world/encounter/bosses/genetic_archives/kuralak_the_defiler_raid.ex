defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.KuralakTheDefilerRaid do
  @moduledoc """
  Kuralak the Defiler encounter - Genetic Archives (Second Boss - 20-man Raid)

  An insectoid horror that drains life and spawns eggs. Features:
  - Siphon channel draining player health
  - Egg spawns that hatch into dangerous adds
  - DNA Siphon requiring tank swaps
  - Vanish phase with spread damage

  ## Strategy
  Phase 1 (100-80%): Interrupt Siphon, tank and spank
  Phase 2 (80-50%): Destroy eggs before hatching, tank swap on DNA Siphon
  Phase 3 (50-20%): Spread during Vanish, burst adds
  Phase 4 (<20%): Burn boss before Final Form overwhelms

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Kuralak the Defiler" do
    boss_id 60002
    health 50_000_000
    level 50
    enrage_timer 660_000
    interrupt_armor 4

    phase :one, health_above: 80 do
      phase_emote "Your essence will feed my children!"

      ability :siphon, cooldown: 12_000, target: :random, interruptible: true do
        telegraph :line, width: 5, length: 30, duration: 4000, color: :purple
        damage 8000, type: :magic
        buff :life_steal, duration: 4000
      end

      ability :chromosome_corruption, cooldown: 18_000, target: :tank do
        debuff :chromosome_corrupted, duration: 15000, stacks: 1
        damage 20000, type: :magic
      end

      ability :mandible_strike, cooldown: 6_000, target: :tank do
        damage 30000, type: :physical
        debuff :bleeding, duration: 8000, stacks: 1
      end

      ability :acidic_spray, cooldown: 10_000 do
        telegraph :cone, angle: 60, length: 18, duration: 2000, color: :green
        damage 25000, type: :poison
      end
    end

    phase :two, health_between: {50, 80} do
      inherit_phase :one
      phase_emote "My children shall feast upon you!"
      enrage_modifier 1.2

      ability :spawn_eggs, cooldown: 25_000 do
        spawn :add, creature_id: 60021, count: 4, spread: true
      end

      ability :dna_siphon, cooldown: 30_000, target: :tank do
        telegraph :circle, radius: 8, duration: 3000, color: :purple
        debuff :dna_drain, duration: 20000, stacks: 1
        damage 40000, type: :magic
      end

      ability :genetic_link, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 6, duration: 2500, color: :purple
        coordination :stack, min_players: 3, damage: 50000
      end

      ability :carapace_slam, cooldown: 15_000 do
        telegraph :circle, radius: 12, duration: 2000, color: :red
        damage 28000, type: :physical
        movement :knockback, distance: 8
      end
    end

    phase :three, health_between: {20, 50} do
      inherit_phase :two
      phase_emote "You cannot escape... I am EVERYWHERE!"
      enrage_modifier 1.35

      ability :genetic_torrent, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 30000, type: :magic
        debuff :gene_torn, duration: 12000, stacks: 1
      end

      ability :vanish, cooldown: 60_000 do
        buff :vanished, duration: 10000
        spawn :add, creature_id: 60022, count: 6, spread: true
      end

      ability :emergence, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 10, duration: 1500, color: :purple
        damage 35000, type: :physical
        movement :knockback, distance: 12
      end

      ability :mass_incubation, cooldown: 40_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 60021, count_per_wave: 3
      end
    end

    phase :four, health_below: 20 do
      inherit_phase :three
      phase_emote "FINAL FORM! CONSUME ALL!"
      enrage_modifier 1.6

      ability :final_form, cooldown: 120_000 do
        buff :final_form, duration: 120000
        buff :damage_increase, duration: 120000
      end

      ability :defiling_wave, cooldown: 12_000 do
        telegraph :room_wide, duration: 3000
        damage 35000, type: :magic
        debuff :defiled, duration: 10000, stacks: 2
      end

      ability :consume, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 5, duration: 2000, color: :purple
        damage 60000, type: :magic
        buff :consumed_power, duration: 15000
      end
    end

    on_death do
      loot_table 60002
    end
  end
end
