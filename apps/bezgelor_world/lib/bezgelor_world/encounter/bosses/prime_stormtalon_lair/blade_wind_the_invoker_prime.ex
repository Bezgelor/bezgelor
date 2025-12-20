defmodule BezgelorWorld.Encounter.Bosses.PrimeStormtalonLair.BladeWindTheInvokerPrime do
  @moduledoc """
  Blade-Wind the Invoker (Prime) - Second boss of Prime Stormtalon's Lair.
  Enhanced shaman with devastating chain lightning and overwhelming adds.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Blade-Wind the Invoker (Prime)" do
    boss_id(11102)
    health(10_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("The spirits demand your destruction!")

      ability :lightning_strike, cooldown: 5_000, target: :tank do
        damage(32000, type: :magic)
        debuff(:conductivity, duration: 10000, stacks: 1)
      end

      ability :thunder_call, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1500, color: :blue)
        damage(25000, type: :magic)
        coordination(:spread, damage: 40000, min_distance: 8)
      end

      ability :static_discharge, cooldown: 15_000 do
        telegraph(:cross, length: 25, width: 5, duration: 2000, color: :blue)
        damage(28000, type: :magic)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("SPIRITS OF THUNDER, ANNIHILATE THEM!")
      enrage_modifier(1.4)

      ability :summon_storm_elementals, cooldown: 25_000 do
        spawn(:add, creature_id: 11121, count: 3, spread: true)
      end

      ability :chain_lightning_cascade, cooldown: 18_000 do
        telegraph(:line, width: 4, length: 30, duration: 1800, color: :blue)
        damage(30000, type: :magic)
        debuff(:shocked, duration: 5000)
      end

      ability :overcharge, cooldown: 30_000 do
        buff(:empowered, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("THE STORM CLAIMS ALL!")
      enrage_modifier(1.7)

      ability :apocalyptic_storm, cooldown: 35_000 do
        telegraph(:room_wide, duration: 4500)
        damage(42000, type: :magic)
      end

      ability :lightning_prison, cooldown: 22_000 do
        telegraph(:circle, radius: 5, duration: 2000, color: :blue)
        damage(35000, type: :magic)
        debuff(:stunned, duration: 3000)
      end
    end

    on_death do
      loot_table(11102)
    end
  end
end
