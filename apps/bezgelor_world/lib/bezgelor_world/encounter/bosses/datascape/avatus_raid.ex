defmodule BezgelorWorld.Encounter.Bosses.Datascape.AvatusRaid do
  @moduledoc """
  Avatus encounter - Datascape (Final Boss - 40-man Raid)

  The Architect of the Datascape and final boss of the 40-man raid. Features:
  - Complex 4-phase encounter with multiple mechanics
  - Digital Annihilation random targeting
  - Data Fragment stack mechanic requiring coordination
  - Omega Protocol and System Purge wipe mechanics
  - Delete All soak requiring full raid coordination

  ## Strategy
  Phase 1 (100-75%): Learn patterns, handle Constructs, avoid Reality Shift
  Phase 2 (75-50%): Stack for Data Fragment, dodge Digital Divide cross
  Phase 3 (50-25%): Position for Oblivion Beam, stack for Digital Storm pull
  Phase 4 (<25%): All healing CDs for Omega Protocol, full raid soak Delete All

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Avatus" do
    boss_id 70009
    health 200_000_000
    level 50
    enrage_timer 1200_000
    interrupt_armor 10

    phase :one, health_above: 75 do
      phase_emote "I AM THE ARCHITECT OF YOUR DESTRUCTION!"

      ability :architects_wrath, cooldown: 10_000, target: :tank do
        damage 90000, type: :physical
        debuff :architects_mark, duration: 15000, stacks: 1
      end

      ability :digital_annihilation, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 15, duration: 2500, color: :purple
        damage 60000, type: :magic
      end

      ability :reality_shift, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 50000, type: :magic
        debuff :reality_warped, duration: 10000, stacks: 1
      end

      ability :spawn_constructs, cooldown: 35_000 do
        spawn :add, creature_id: 70092, count: 4, spread: true
      end

      ability :data_pulse, cooldown: 12_000 do
        telegraph :circle, radius: 12, duration: 2000, color: :purple
        damage 45000, type: :magic
      end

      ability :code_injection, cooldown: 20_000, target: :random do
        telegraph :line, width: 5, length: 40, duration: 2000, color: :purple
        damage 50000, type: :magic
        debuff :injected_code, duration: 8000
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase :one
      phase_emote "YOU ARE NOTHING BUT DATA TO BE DELETED!"
      enrage_modifier 1.3

      ability :digital_divide, cooldown: 25_000 do
        telegraph :cross, length: 50, width: 10, duration: 3500, color: :purple
        damage 70000, type: :magic
      end

      ability :corruption_matrix, cooldown: 20_000 do
        telegraph :room_wide, duration: 3000
        damage 45000, type: :magic
        debuff :corrupted_matrix, duration: 12000, stacks: 1
      end

      ability :data_fragment, cooldown: 40_000, target: :random do
        telegraph :circle, radius: 10, duration: 4000, color: :blue
        coordination :stack, min_players: 8, damage: 200000
      end

      ability :system_error, cooldown: 22_000 do
        telegraph :circle, radius: 18, duration: 2500, color: :purple
        damage 55000, type: :magic
        spawn :add, creature_id: 70092, count: 2, spread: true
      end

      ability :virtual_prison, cooldown: 35_000, target: :random do
        telegraph :circle, radius: 6, duration: 3000, color: :purple
        debuff :imprisoned, duration: 6000
        damage 40000, type: :magic
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase :two
      phase_emote "THE DATASCAPE BENDS TO MY WILL!"
      enrage_modifier 1.5

      ability :big_bang, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 75000, type: :magic
        debuff :existence_fractured, duration: 15000, stacks: 1
      end

      ability :oblivion_beam, cooldown: 30_000 do
        telegraph :line, width: 12, length: 60, duration: 4000, color: :purple
        damage 100000, type: :magic
      end

      ability :digital_storm, cooldown: 25_000 do
        telegraph :circle, radius: 25, duration: 3000, color: :purple
        damage 65000, type: :magic
        movement :pull, distance: 10
      end

      ability :reality_collapse, cooldown: 40_000 do
        telegraph :donut, inner_radius: 8, outer_radius: 25, duration: 4000, color: :purple
        damage 80000, type: :magic
      end

      ability :architect_rage, cooldown: 45_000 do
        buff :enraged_architect, duration: 20000
        buff :damage_increase, duration: 20000
        spawn :add, creature_id: 70092, count: 6, spread: true
      end
    end

    phase :four, health_below: 25 do
      inherit_phase :three
      phase_emote "THIS CANNOT BE! I AM AVATUS! I AM PERFECTION!"
      enrage_modifier 1.8

      ability :omega_protocol, cooldown: 40_000 do
        telegraph :room_wide, duration: 5000
        damage 90000, type: :magic
        debuff :omega_marked, duration: 20000, stacks: 2
      end

      ability :system_purge, cooldown: 50_000 do
        telegraph :room_wide, duration: 6000
        damage 100000, type: :magic
      end

      ability :delete_all, cooldown: 60_000 do
        telegraph :circle, radius: 12, duration: 5000, color: :red
        coordination :soak, base_damage: 300000, required_players: 20
      end

      ability :final_calculation, cooldown: 90_000 do
        telegraph :room_wide, duration: 8000
        damage 150000, type: :magic
      end

      ability :digital_apocalypse, cooldown: 35_000 do
        telegraph :cross, length: 55, width: 12, duration: 4000, color: :purple
        damage 85000, type: :magic
        spawn :add, creature_id: 70092, count: 4, spread: true
      end

      ability :existence_erasure, cooldown: 28_000, target: :random do
        telegraph :circle, radius: 8, duration: 3000, color: :red
        coordination :spread, min_distance: 15, damage: 100000
      end

      ability :final_form, cooldown: 120_000 do
        buff :perfected_form, duration: 60000
        buff :damage_increase, duration: 60000
        telegraph :room_wide, duration: 3000
        damage 60000, type: :magic
      end
    end

    on_death do
      loot_table 70009
      achievement 7009  # Datascape complete
      achievement 7100  # Realm First: Avatus (conditional)
    end
  end
end
