defmodule BezgelorWorld.Encounter.Bosses.Datascape.SystemDaemonsRaid do
  @moduledoc """
  System Daemons encounter - Datascape (First Boss - 40-man Raid)

  Dual digital constructs that must be balanced and killed together. Features:
  - Binary and Null forms sharing health pools
  - System Link spread mechanic requiring positioning
  - Data Corruption random targeting
  - Phase 3 Blue Screen soak mechanic

  ## Strategy
  Phase 1 (100-70%): Split raid, balance damage between Binary and Null
  Phase 2 (70-40%): Handle Disconnect, avoid Purge cross pattern
  Phase 3 (<40%): Soak Blue Screen, burn before Total Wipe

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "System Daemons" do
    boss_id(70001)
    health(120_000_000)
    level(50)
    enrage_timer(900_000)
    interrupt_armor(6)

    phase :one, health_above: 70 do
      phase_emote("BINARY TERROR INITIATING. PREPARE FOR DELETION.")

      ability :binary_strike, cooldown: 10_000, target: :tank do
        damage(60000, type: :physical)
        debuff(:binary_resonance, duration: 10000, stacks: 1)
      end

      ability :data_corruption, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :purple)
        damage(40000, type: :magic)
        debuff(:corrupted_data, duration: 12000, stacks: 1)
      end

      ability :null_beam, cooldown: 20_000 do
        telegraph(:line, width: 8, length: 50, duration: 2500, color: :blue)
        damage(50000, type: :magic)
      end

      ability :system_link, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 5, duration: 3000, color: :purple)
        coordination(:spread, min_distance: 10, damage: 70000)
      end

      ability :probe_spawn, cooldown: 30_000 do
        spawn(:add, creature_id: 70012, count: 4, spread: true)
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase(:one)
      phase_emote("SYNCHRONIZING ATTACK PROTOCOLS.")
      enrage_modifier(1.3)

      ability :disconnect, cooldown: 40_000 do
        telegraph(:room_wide, duration: 5000)
        damage(55000, type: :magic)
        debuff(:disconnected, duration: 8000, stacks: 1)
      end

      ability :purge, cooldown: 30_000 do
        telegraph(:cross, length: 40, width: 10, duration: 3000, color: :red)
        damage(60000, type: :magic)
      end

      ability :defrag, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 8, duration: 2000, color: :purple)
        debuff(:fragmented, duration: 15000, stacks: 2)
      end

      ability :cascade_error, cooldown: 35_000 do
        telegraph(:circle, radius: 18, duration: 2500, color: :purple)
        damage(45000, type: :magic)
        spawn(:add, creature_id: 70012, count: 2, spread: true)
      end
    end

    phase :three, health_below: 40 do
      inherit_phase(:two)
      phase_emote("CRITICAL ERROR. INITIATING PURGE PROTOCOL.")
      enrage_modifier(1.5)

      ability :system_crash, cooldown: 35_000 do
        telegraph(:room_wide, duration: 4000)
        damage(70000, type: :magic)
        debuff(:crashed, duration: 10000, stacks: 1)
      end

      ability :blue_screen, cooldown: 45_000 do
        telegraph(:circle, radius: 8, duration: 4000, color: :blue)
        coordination(:soak, base_damage: 150_000, required_players: 10)
      end

      ability :total_wipe, cooldown: 60_000 do
        telegraph(:room_wide, duration: 6000)
        damage(80000, type: :magic)
      end

      ability :memory_overflow, cooldown: 25_000 do
        telegraph(:circle, radius: 20, duration: 3000, color: :purple)
        damage(50000, type: :magic)
        movement(:knockback, distance: 12)
      end

      ability :final_sync, cooldown: 50_000 do
        buff(:synchronized_fury, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    on_death do
      loot_table(70001)
      # Datascape: System Daemons
      achievement(7001)
    end
  end
end
