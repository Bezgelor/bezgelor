defmodule BezgelorWorld.Encounter.Bosses.Shiphands.RageLogic do
  @moduledoc """
  Rage Logic Terror From Beyond shiphand boss.
  Eldritch horror with reality-bending attacks.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Logic Horror" do
    boss_id 60601
    health 150_000
    level 34
    enrage_timer 180_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "YOUR LOGIC... IS FLAWED..."

      ability :mind_flay, cooldown: 5_000, target: :tank do
        damage 2200, type: :shadow
      end

      ability :reality_tear, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :purple
        damage 1900, type: :magic
      end

      ability :illogical_beam, cooldown: 15_000 do
        telegraph :line, width: 4, length: 20, duration: 2000, color: :purple
        damage 2100, type: :shadow
      end
    end

    phase :two, health_between: [25, 50] do
      inherit_phase :one
      phase_emote "EMBRACE... THE CHAOS..."
      enrage_modifier 1.3

      ability :spawn_paradox, cooldown: 25_000 do
        spawn :add, creature_id: 60611, count: 2, spread: true
      end

      ability :entropy_field, cooldown: 20_000 do
        telegraph :donut, inner_radius: 3, outer_radius: 10, duration: 2000, color: :purple
        damage 2400, type: :shadow
      end
    end

    phase :three, health_below: 25 do
      inherit_phase :two
      phase_emote "ALL... BECOMES... NOTHING..."
      enrage_modifier 1.5

      ability :void_collapse, cooldown: 25_000 do
        telegraph :room_wide, duration: 3000
        damage 3000, type: :shadow
      end
    end

    on_death do
      loot_table 60601
    end
  end
end
