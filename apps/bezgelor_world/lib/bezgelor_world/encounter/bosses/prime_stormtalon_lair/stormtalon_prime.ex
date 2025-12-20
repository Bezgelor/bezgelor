defmodule BezgelorWorld.Encounter.Bosses.PrimeStormtalonLair.StormtalonPrime do
  @moduledoc """
  Stormtalon (Prime) - Final boss of Prime Stormtalon's Lair.
  The ultimate storm bird challenge with 4 phases of deadly mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon (Prime)" do
    boss_id(11103)
    health(15_000_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(5)

    phase :one, health_above: 70 do
      phase_emote("SCREEEEE! YOU DARE CHALLENGE THE STORM ITSELF?!")

      ability :talon_rend, cooldown: 5_000, target: :tank do
        damage(38000, type: :physical)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end

      ability :lightning_storm, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :blue)
        damage(30000, type: :magic)
        coordination(:spread, damage: 50000, min_distance: 8)
      end

      ability :wing_buffet, cooldown: 15_000 do
        telegraph(:cone, angle: 90, length: 28, duration: 2000, color: :blue)
        damage(32000, type: :physical)
        movement(:knockback, distance: 12)
      end
    end

    phase :two, health_between: [45, 70] do
      inherit_phase(:one)
      phase_emote("THE STORM GROWS STRONGER!")
      enrage_modifier(1.3)

      ability :eye_of_the_storm, cooldown: 22_000 do
        telegraph(:donut, inner_radius: 6, outer_radius: 18, duration: 2500, color: :blue)
        damage(45000, type: :magic)
      end

      ability :call_lightning, cooldown: 18_000 do
        telegraph(:circle, radius: 6, duration: 1500, color: :blue)
        damage(35000, type: :magic)
        debuff(:shocked, duration: 6000)
      end

      ability :summon_stormlings, cooldown: 30_000 do
        spawn(:add, creature_id: 11131, count: 3, spread: true)
      end
    end

    phase :three, health_between: [20, 45] do
      inherit_phase(:two)
      phase_emote("I AM THE HURRICANE! I AM DESTRUCTION!")
      enrage_modifier(1.55)

      ability :tempest_fury, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :magic)
      end

      ability :static_burst, cooldown: 20_000 do
        telegraph(:cross, length: 30, width: 6, duration: 2000, color: :blue)
        damage(42000, type: :magic)
      end

      ability :focused_storm, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 5, duration: 1500, color: :blue)
        coordination(:stack, damage: 60000, required_players: 3)
      end
    end

    phase :four, health_below: 20 do
      inherit_phase(:three)
      phase_emote("THE STORM ETERNAL WILL CONSUME YOU ALL!")
      enrage_modifier(1.9)

      ability :apocalyptic_tempest, cooldown: 35_000 do
        telegraph(:room_wide, duration: 5000)
        damage(70000, type: :magic)
      end

      ability :thunder_god, cooldown: 25_000 do
        buff(:thunder_god, duration: 20000)
        buff(:damage_increase, duration: 20000)
        buff(:speed_increase, duration: 20000)
      end

      ability :ultimate_lightning, cooldown: 18_000 do
        telegraph(:cross, length: 35, width: 8, duration: 2000, color: :blue)
        damage(55000, type: :magic)
        debuff(:stunned, duration: 2000)
      end
    end

    on_death do
      loot_table(11103)
      # Prime Stormtalon's Lair completion
      achievement(1110)
    end
  end
end
