defmodule BezgelorWorld.Encounter.Bosses.Expeditions.FragmentZero do
  @moduledoc """
  Fragment Zero expedition bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Eldan Construct" do
    boss_id(51301)
    health(1_000_000)
    level(45)
    enrage_timer(300_000)
    interrupt_armor(3)

    phase :one, health_above: 45 do
      phase_emote("ANALYZING THREAT... COMMENCING ELIMINATION.")

      ability :laser_beam, cooldown: 8_000, target: :tank do
        damage(11000, type: :magic)
      end

      ability :targeting_grid, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :blue)
        damage(9000, type: :magic)
      end

      ability :plasma_wave, cooldown: 15_000 do
        telegraph(:line, width: 6, length: 30, duration: 2000, color: :blue)
        damage(10000, type: :magic)
      end
    end

    phase :two, health_below: 45 do
      inherit_phase(:one)
      phase_emote("ENGAGING COMBAT PROTOCOLS.")
      enrage_modifier(1.35)

      ability :system_overload, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(12000, type: :magic)
      end

      ability :deploy_drones, cooldown: 28_000 do
        spawn(:add, creature_id: 51311, count: 3, spread: true)
      end

      ability :defense_grid, cooldown: 22_000 do
        telegraph(:cross, length: 28, width: 5, duration: 2500, color: :blue)
        damage(11000, type: :magic)
      end
    end

    on_death do
      loot_table(51301)
    end
  end

  boss "Prime Artificial" do
    boss_id(51302)
    health(1_500_000)
    level(45)
    enrage_timer(360_000)
    interrupt_armor(4)

    phase :one, health_above: 50 do
      phase_emote("I AM THE PINNACLE OF ELDAN ENGINEERING.")

      ability :prime_strike, cooldown: 8_000, target: :tank do
        damage(14000, type: :magic)
      end

      ability :data_corruption, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :purple)
        damage(11000, type: :magic)
        debuff(:corrupted, duration: 8000, stacks: 1)
      end

      ability :arc_lightning, cooldown: 12_000 do
        telegraph(:cone, angle: 60, length: 28, duration: 2000, color: :blue)
        damage(12000, type: :magic)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("ACTIVATING EMERGENCY PROTOCOLS.")
      enrage_modifier(1.4)

      ability :system_purge, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4500)
        damage(14000, type: :magic)
      end

      ability :spawn_guardians, cooldown: 28_000 do
        spawn(:add, creature_id: 51321, count: 4, spread: true)
      end

      ability :override_beam, cooldown: 20_000 do
        telegraph(:line, width: 8, length: 40, duration: 2500, color: :blue)
        damage(15000, type: :magic)
      end

      ability :final_protocol, cooldown: 35_000 do
        buff(:overcharged, duration: 12000)
        buff(:damage_increase, duration: 12000)
      end
    end

    on_death do
      loot_table(51302)
      # Fragment Zero completion
      achievement(5130)
    end
  end
end
