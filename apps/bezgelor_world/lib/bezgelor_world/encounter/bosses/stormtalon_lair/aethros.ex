defmodule BezgelorWorld.Encounter.Bosses.StormtalonLair.Aethros do
  @moduledoc """
  Aethros - First boss of Stormtalon's Lair (Normal).
  Wind elemental with tornado and gust mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Aethros" do
    boss_id 10101
    health 450_000
    level 20
    enrage_timer 180_000
    interrupt_armor 1

    phase :one, health_above: 50 do
      phase_emote "THE WINDS HOWL AT MY COMMAND!"

      ability :gust_slash, cooldown: 6_000, target: :tank do
        damage 3500, type: :physical
      end

      ability :wind_burst, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1500, color: :blue
        damage 2800, type: :magic
        movement :knockback, distance: 5
      end

      ability :cyclone, cooldown: 15_000 do
        telegraph :line, width: 4, length: 20, duration: 1800, color: :blue
        damage 3000, type: :magic
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "FEEL THE FURY OF THE STORM!"
      enrage_modifier 1.2

      ability :tornado, cooldown: 18_000 do
        telegraph :circle, radius: 8, duration: 2000, color: :blue
        damage 3500, type: :magic
        debuff :slowed, duration: 3000
      end
    end

    on_death do
      loot_table 10101
    end
  end
end
