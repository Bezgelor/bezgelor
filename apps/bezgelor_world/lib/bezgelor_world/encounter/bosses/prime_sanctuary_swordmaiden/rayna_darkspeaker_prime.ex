defmodule BezgelorWorld.Encounter.Bosses.PrimeSanctuarySwordmaiden.RaynaDarkspeakerPrime do
  @moduledoc """
  Rayna Darkspeaker (Prime) - First boss of Prime SSM.
  Shadow shaman with devastating void magic.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Rayna Darkspeaker (Prime)" do
    boss_id(14101)
    health(8_000_000)
    level(50)
    enrage_timer(300_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("The shadows hunger for your souls!")

      ability :shadow_bolt, cooldown: 5_000, target: :tank do
        damage(30000, type: :shadow)
        debuff(:shadow_vulnerability, duration: 10000, stacks: 1)
      end

      ability :void_eruption, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :purple)
        damage(25000, type: :shadow)
        coordination(:spread, damage: 40000, min_distance: 6)
      end

      ability :dark_wave, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 22, duration: 2000, color: :purple)
        damage(28000, type: :shadow)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("DARKNESS CONSUMES ALL!")
      enrage_modifier(1.4)

      ability :summon_shades, cooldown: 25_000 do
        spawn(:add, creature_id: 14111, count: 3, spread: true)
      end

      ability :shadow_nova, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3000)
        damage(35000, type: :shadow)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("EMBRACE THE ETERNAL DARKNESS!")
      enrage_modifier(1.7)

      ability :void_apocalypse, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(50000, type: :shadow)
      end

      ability :dark_cross, cooldown: 18_000 do
        telegraph(:cross, length: 28, width: 5, duration: 2000, color: :purple)
        damage(42000, type: :shadow)
      end
    end

    on_death do
      loot_table(14101)
    end
  end
end
