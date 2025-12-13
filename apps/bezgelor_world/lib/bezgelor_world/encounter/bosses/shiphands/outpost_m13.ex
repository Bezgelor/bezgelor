defmodule BezgelorWorld.Encounter.Bosses.Shiphands.OutpostM13 do
  @moduledoc """
  Outpost M-13 shiphand boss.
  Rogue Eldan prototype with tech attacks.
  """

  use BezgelorWorld.Encounter.DSL

  boss "M-13 Prototype" do
    boss_id 60401
    health 90_000
    level 22
    enrage_timer 150_000
    interrupt_armor 1

    phase :one, health_above: 40 do
      phase_emote "INTRUDER DETECTED. ENGAGING DEFENSE PROTOCOLS."

      ability :plasma_bolt, cooldown: 5_000, target: :tank do
        damage 1500, type: :magic
      end

      ability :laser_sweep, cooldown: 10_000 do
        telegraph :cone, angle: 45, length: 15, duration: 1500, color: :red
        damage 1300, type: :magic
      end

      ability :deploy_turret, cooldown: 25_000 do
        spawn :add, creature_id: 60411, count: 1, spread: false
      end
    end

    phase :two, health_below: 40 do
      inherit_phase :one
      phase_emote "DAMAGE CRITICAL. ACTIVATING OVERDRIVE."
      enrage_modifier 1.3

      ability :overload_beam, cooldown: 15_000 do
        telegraph :line, width: 4, length: 20, duration: 2000, color: :red
        damage 1800, type: :magic
      end

      ability :emp_pulse, cooldown: 20_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :blue
        damage 1600, type: :magic
        debuff :slowed, duration: 4000
      end
    end

    on_death do
      loot_table 60401
    end
  end
end
