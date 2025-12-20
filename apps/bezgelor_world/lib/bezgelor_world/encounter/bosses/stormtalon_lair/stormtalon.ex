defmodule BezgelorWorld.Encounter.Bosses.StormtalonLair.Stormtalon do
  @moduledoc """
  Stormtalon - Final boss of Stormtalon's Lair (Normal).
  Giant storm bird with devastating lightning and wind attacks.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon" do
    boss_id(10103)
    health(900_000)
    level(22)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 60 do
      phase_emote("SCREEEEE! INTRUDERS IN MY DOMAIN!")

      ability :talon_strike, cooldown: 6_000, target: :tank do
        damage(4500, type: :physical)
        debuff(:bleeding, duration: 6000, stacks: 1)
      end

      ability :lightning_storm, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :blue)
        damage(3500, type: :magic)
      end

      ability :wing_buffet, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 20, duration: 2000, color: :blue)
        damage(3800, type: :physical)
        movement(:knockback, distance: 6)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("THE STORM INTENSIFIES!")
      enrage_modifier(1.25)

      ability :eye_of_the_storm, cooldown: 25_000 do
        telegraph(:donut, inner_radius: 4, outer_radius: 12, duration: 2500, color: :blue)
        damage(5000, type: :magic)
      end

      ability :call_lightning, cooldown: 20_000 do
        telegraph(:circle, radius: 5, duration: 1500, color: :blue)
        damage(4000, type: :magic)
        debuff(:shocked, duration: 5000)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("YOU WILL NOT SURVIVE MY WRATH!")
      enrage_modifier(1.4)

      ability :tempest, cooldown: 30_000 do
        telegraph(:room_wide, duration: 3000)
        damage(5500, type: :magic)
      end

      ability :static_burst, cooldown: 18_000 do
        telegraph(:cross, length: 20, width: 4, duration: 2000, color: :blue)
        damage(4500, type: :magic)
      end
    end

    on_death do
      loot_table(10103)
      # Stormtalon's Lair completion
      achievement(1010)
    end
  end
end
