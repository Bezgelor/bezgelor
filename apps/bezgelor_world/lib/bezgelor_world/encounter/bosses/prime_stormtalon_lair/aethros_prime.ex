defmodule BezgelorWorld.Encounter.Bosses.PrimeStormtalonLair.AethrosPrime do
  @moduledoc """
  Aethros (Prime) - First boss of Prime Stormtalon's Lair.
  Extreme difficulty with punishing mechanics and coordination requirements.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Aethros (Prime)" do
    boss_id(11101)
    health(8_500_000)
    level(50)
    enrage_timer(360_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("THE TEMPEST AWAKENS!")

      ability :gust_slash, cooldown: 5_000, target: :tank do
        damage(28000, type: :physical)
        debuff(:wind_vulnerability, duration: 8000, stacks: 1)
      end

      ability :cyclone_barrage, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1500, color: :blue)
        damage(22000, type: :magic)
        coordination(:spread, damage: 35000, min_distance: 6)
      end

      ability :gale_force, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 25, duration: 2000, color: :blue)
        damage(25000, type: :magic)
        movement(:knockback, distance: 10)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("THE STORM INTENSIFIES!")
      enrage_modifier(1.35)

      ability :tornado_field, cooldown: 20_000 do
        telegraph(:circle, radius: 6, duration: 2000, color: :blue)
        damage(28000, type: :magic)
        spawn(:add, creature_id: 11112, count: 3, spread: true)
      end

      ability :wind_prison, cooldown: 25_000, target: :healer do
        debuff(:imprisoned, duration: 6000)
        spawn(:add, creature_id: 11111, count: 2, spread: true)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("WITNESS THE FURY OF THE ETERNAL STORM!")
      enrage_modifier(1.6)

      ability :cataclysmic_gale, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(35000, type: :magic)
      end

      ability :eye_of_aethros, cooldown: 22_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 15, duration: 2500, color: :blue)
        damage(40000, type: :magic)
      end
    end

    on_death do
      loot_table(11101)
    end
  end
end
