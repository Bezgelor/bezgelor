defmodule BezgelorWorld.Encounter.Bosses.Shiphands.Gauntlet do
  @moduledoc """
  Gauntlet shiphand boss.
  Arena champion with escalating combat mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Arena Champion" do
    boss_id(60701)
    health(200_000)
    level(45)
    enrage_timer(240_000)
    interrupt_armor(2)

    phase :one, health_above: 60 do
      phase_emote("Welcome to the Gauntlet! Let's see what you've got!")

      ability :champion_strike, cooldown: 5_000, target: :tank do
        damage(3000, type: :physical)
      end

      ability :arena_slam, cooldown: 12_000 do
        telegraph(:circle, radius: 7, duration: 1800, color: :red)
        damage(2500, type: :physical)
        movement(:knockback, distance: 5)
      end

      ability :spinning_blade, cooldown: 15_000 do
        telegraph(:cone, angle: 120, length: 15, duration: 2000, color: :red)
        damage(2800, type: :physical)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("Not bad! Time to step it up!")
      enrage_modifier(1.3)

      ability :call_gladiators, cooldown: 30_000 do
        spawn(:add, creature_id: 60711, count: 2, spread: true)
      end

      ability :death_from_above, cooldown: 18_000, target: :farthest do
        telegraph(:circle, radius: 6, duration: 2000, color: :red)
        damage(3200, type: :physical)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("FINAL ROUND! GIVE ME EVERYTHING!")
      enrage_modifier(1.5)

      ability :champion_fury, cooldown: 25_000 do
        telegraph(:room_wide, duration: 3000)
        damage(4000, type: :physical)
      end

      ability :execute, cooldown: 20_000, target: :lowest_health do
        telegraph(:line, width: 3, length: 25, duration: 1500, color: :red)
        damage(5000, type: :physical)
      end
    end

    on_death do
      loot_table(60701)
      # Gauntlet completion
      achievement(6070)
    end
  end
end
