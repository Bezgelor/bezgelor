defmodule BezgelorWorld.Encounter.Bosses.Datascape.ElementalPairsLogicRaid do
  @moduledoc """
  Elemental Pairs: Logic encounter - Datascape (Seventh Boss - 40-man Raid)

  One of four elemental pairs that must be killed within 20 seconds of each other.
  Logic element features digital/magic damage and computational mechanics. Features:
  - Calculation buff that increases damage over time
  - Binary Blast random targeting
  - Logic Construct adds that buff the boss
  - Fatal Error spread mechanic

  ## Strategy
  Phase 1 (100-50%): Interrupt Calculation, avoid Debug lines
  Phase 2 (<50%): Kill Constructs before they stack buffs, spread for Fatal Error
  IMPORTANT: Must kill within 20 seconds of Fire element or both heal to full

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Elemental Pairs - Logic" do
    boss_id(70007)
    health(100_000_000)
    level(50)
    enrage_timer(720_000)
    interrupt_armor(5)

    phase :one, health_above: 50 do
      phase_emote("CALCULATING OPTIMAL DESTRUCTION.")

      ability :data_spike, cooldown: 10_000, target: :tank do
        damage(65000, type: :magic)
        debuff(:data_corrupted, duration: 10000, stacks: 1)
      end

      ability :binary_blast, cooldown: 14_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :blue)
        damage(45000, type: :magic)
      end

      ability :calculation, cooldown: 25_000, interruptible: true do
        buff(:calculating, duration: 8000)
        buff(:damage_increase, duration: 8000)
      end

      ability :debug, cooldown: 18_000 do
        telegraph(:line, width: 6, length: 35, duration: 2500, color: :blue)
        damage(40000, type: :magic)
      end

      ability :syntax_error, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 6, duration: 1500, color: :blue)
        damage(38000, type: :magic)
        debuff(:confused, duration: 4000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("LOGIC DICTATES YOUR DESTRUCTION.")
      enrage_modifier(1.4)

      ability :system_overload, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :magic)
        debuff(:overloaded, duration: 12000, stacks: 1)
      end

      ability :spawn_constructs, cooldown: 40_000 do
        spawn(:add, creature_id: 70072, count: 4, spread: true)
      end

      ability :fatal_error, cooldown: 35_000, target: :random do
        telegraph(:circle, radius: 8, duration: 3000, color: :red)
        coordination(:spread, min_distance: 10, damage: 80000)
      end

      ability :recursive_loop, cooldown: 22_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :blue)
        damage(50000, type: :magic)
        movement(:pull, distance: 8)
      end

      ability :null_pointer, cooldown: 28_000, target: :random do
        telegraph(:line, width: 8, length: 40, duration: 2500, color: :blue)
        damage(60000, type: :magic)
      end

      ability :compile_error, cooldown: 45_000 do
        buff(:error_state, duration: 12000)
        telegraph(:room_wide, duration: 3000)
        damage(45000, type: :magic)
        spawn(:add, creature_id: 70072, count: 2, spread: true)
      end
    end

    on_death do
      loot_table(70007)
    end
  end
end
