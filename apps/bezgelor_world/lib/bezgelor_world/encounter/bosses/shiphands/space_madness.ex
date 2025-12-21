defmodule BezgelorWorld.Encounter.Bosses.Shiphands.SpaceMadness do
  @moduledoc """
  Space Madness shiphand boss.
  Corrupted crew member driven mad by void exposure.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Corrupted Crewman" do
    boss_id(60501)
    health(110_000)
    level(28)
    enrage_timer(180_000)
    interrupt_armor(1)

    phase :one, health_above: 50 do
      phase_emote("They're everywhere! THE VOICES!")

      ability :frenzied_slash, cooldown: 5_000, target: :tank do
        damage(1800, type: :physical)
      end

      ability :madness_burst, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 5, duration: 1500, color: :purple)
        damage(1500, type: :shadow)
        debuff(:confused, duration: 3000)
      end

      ability :paranoid_sweep, cooldown: 15_000 do
        telegraph(:cone, angle: 90, length: 18, duration: 2000, color: :red)
        damage(1700, type: :physical)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("NO! YOU'RE ONE OF THEM!")
      enrage_modifier(1.3)

      ability :hallucination, cooldown: 25_000 do
        spawn(:add, creature_id: 60511, count: 2, spread: true)
      end

      ability :void_whispers, cooldown: 20_000 do
        telegraph(:room_wide, duration: 2500)
        damage(2000, type: :shadow)
        debuff(:terrified, duration: 3000)
      end
    end

    on_death do
      loot_table(60501)
    end
  end
end
