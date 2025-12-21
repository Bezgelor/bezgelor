defmodule BezgelorWorld.Encounter.Bosses.PrimeSanctuarySwordmaiden.MoldwoodOverlordPrime do
  @moduledoc """
  Moldwood Overlord (Prime) - Third boss of Prime SSM.
  Corrupted treant with decay and corruption mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Moldwood Overlord (Prime)" do
    boss_id(14103)
    health(10_000_000)
    level(50)
    enrage_timer(360_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("The corruption spreads...")

      ability :corrupted_slam, cooldown: 5_000, target: :tank do
        damage(35000, type: :nature)
        debuff(:corrupted, duration: 10000, stacks: 1)
      end

      ability :decay_burst, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :brown)
        damage(28000, type: :nature)
        debuff(:decaying, duration: 8000)
      end

      ability :root_sweep, cooldown: 15_000 do
        telegraph(:cone, angle: 90, length: 25, duration: 2000, color: :brown)
        damage(32000, type: :nature)
        movement(:knockback, distance: 8)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("ALL WILL ROT!")
      enrage_modifier(1.4)

      ability :spawn_saplings, cooldown: 25_000 do
        spawn(:add, creature_id: 14131, count: 4, spread: true)
      end

      ability :blight_zone, cooldown: 20_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :brown)
        damage(38000, type: :nature)
        debuff(:decaying, duration: 10000)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("DECAY IS ETERNAL!")
      enrage_modifier(1.7)

      ability :corruption_wave, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(52000, type: :nature)
        debuff(:corrupted, duration: 15000, stacks: 3)
      end

      ability :root_cross, cooldown: 18_000 do
        telegraph(:cross, length: 30, width: 6, duration: 2000, color: :brown)
        damage(45000, type: :nature)
      end
    end

    on_death do
      loot_table(14103)
    end
  end
end
