defmodule BezgelorWorld.Encounter.Bosses.Datascape.LimboInfomatrixRaid do
  @moduledoc """
  Limbo Infomatrix encounter - Datascape (Fourth Boss - 40-man Raid)

  A sentient data construct managing the Datascape's information systems. Features:
  - Logic Bomb stack mechanic requiring grouping
  - Process adds that must be killed quickly
  - Virus Upload spreading debuff
  - Blue Screen of Death wipe mechanic

  ## Strategy
  Phase 1 (100-75%): Stack for Logic Bomb, kill Process adds quickly
  Phase 2 (75-50%): Avoid Firewall lines, cleanse Virus before spreading
  Phase 3 (50-25%): Handle Cascade Failure, spread for Root Access
  Phase 4 (<25%): Burn through Blue Screen of Death, avoid Format All

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Limbo Infomatrix" do
    boss_id(70004)
    health(150_000_000)
    level(50)
    enrage_timer(1080_000)
    interrupt_armor(8)

    phase :one, health_above: 75 do
      phase_emote("PROCESSING... THREAT DETECTED.")

      ability :data_stream, cooldown: 12_000, target: :tank do
        damage(65000, type: :magic)
        debuff(:data_overload, duration: 10000, stacks: 1)
      end

      ability :matrix_cage, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 8, duration: 2500, color: :blue)
        damage(40000, type: :magic)
        debuff(:caged, duration: 6000)
      end

      ability :logic_bomb, cooldown: 30_000, target: :random do
        telegraph(:circle, radius: 6, duration: 3500, color: :red)
        coordination(:stack, min_players: 5, damage: 120_000)
      end

      ability :spawn_processes, cooldown: 40_000 do
        spawn(:add, creature_id: 70042, count: 6, spread: true)
      end

      ability :data_spike, cooldown: 15_000, target: :random do
        telegraph(:line, width: 4, length: 35, duration: 2000, color: :blue)
        damage(45000, type: :magic)
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase(:one)
      phase_emote("ENGAGING COMBAT SUBROUTINES.")
      enrage_modifier(1.2)

      ability :firewall, cooldown: 25_000 do
        telegraph(:line, width: 15, length: 50, duration: 3000, color: :red)
        damage(60000, type: :fire)
      end

      ability :virus_upload, cooldown: 45_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :green)
        debuff(:infected, duration: 30000, stacks: 1)
        damage(25000, type: :magic)
      end

      ability :memory_leak, cooldown: 20_000 do
        telegraph(:room_wide, duration: 3000)
        damage(35000, type: :magic)
        debuff(:memory_fragmented, duration: 8000, stacks: 1)
      end

      ability :recursive_function, cooldown: 28_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2500, color: :blue)
        damage(50000, type: :magic)
        spawn(:add, creature_id: 70042, count: 2, spread: true)
      end

      ability :segfault, cooldown: 35_000 do
        telegraph(:cross, length: 35, width: 6, duration: 2500, color: :blue)
        damage(55000, type: :magic)
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase(:two)
      phase_emote("SECURITY PROTOCOL ALPHA ENGAGED.")
      enrage_modifier(1.4)

      ability :cascade_failure, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :magic)
        debuff(:system_failure, duration: 12000, stacks: 1)
      end

      ability :root_access, cooldown: 35_000, target: :random do
        telegraph(:circle, radius: 8, duration: 3000, color: :red)
        coordination(:spread, min_distance: 12, damage: 80000)
      end

      ability :system_restore, cooldown: 60_000 do
        buff(:restoring, duration: 15000)
        buff(:damage_reduction, duration: 15000)
      end

      ability :denial_of_service, cooldown: 25_000 do
        telegraph(:cone, angle: 120, length: 35, duration: 2500, color: :blue)
        damage(60000, type: :magic)
        movement(:knockback, distance: 12)
      end

      ability :buffer_overflow, cooldown: 40_000 do
        telegraph(:circle, radius: 20, duration: 3000, color: :blue)
        damage(70000, type: :magic)
        spawn(:add, creature_id: 70042, count: 4, spread: true)
      end
    end

    phase :four, health_below: 25 do
      inherit_phase(:three)
      phase_emote("INITIATING KERNEL PANIC!")
      enrage_modifier(1.7)

      ability :blue_screen_of_death, cooldown: 40_000 do
        telegraph(:room_wide, duration: 5000)
        damage(75000, type: :magic)
        debuff(:critical_error, duration: 20000, stacks: 2)
      end

      ability :core_dump, cooldown: 50_000 do
        telegraph(:circle, radius: 20, duration: 4000, color: :blue)
        damage(100_000, type: :magic)
        movement(:pull, distance: 15)
      end

      ability :format_all, cooldown: 75_000 do
        telegraph(:room_wide, duration: 7000)
        damage(120_000, type: :magic)
      end

      ability :kernel_panic, cooldown: 30_000 do
        telegraph(:room_wide, duration: 3000)
        damage(50000, type: :magic)
        spawn(:add, creature_id: 70042, count: 8, spread: true)
      end

      ability :final_exception, cooldown: 55_000 do
        buff(:exception_state, duration: 15000)
        buff(:damage_increase, duration: 15000)
        telegraph(:room_wide, duration: 4000)
        damage(80000, type: :magic)
      end
    end

    on_death do
      loot_table(70004)
      # Datascape: Limbo Infomatrix
      achievement(7004)
    end
  end
end
