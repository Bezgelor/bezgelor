defmodule BezgelorWorld.Encounter.Bosses.Expeditions.RiotInTheVoid do
  @moduledoc """
  Riot in the Void expedition bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Void Terror" do
    boss_id 51001
    health 800_000
    level 35
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 40 do
      phase_emote "THE VOID CONSUMES!"

      ability :void_strike, cooldown: 8_000, target: :tank do
        damage 8000, type: :shadow
      end

      ability :void_pool, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :purple
        damage 6000, type: :shadow
      end

      ability :terror_wave, cooldown: 12_000 do
        telegraph :cone, angle: 60, length: 20, duration: 1800, color: :purple
        damage 7000, type: :shadow
      end
    end

    phase :two, health_below: 40 do
      inherit_phase :one
      phase_emote "EMBRACE THE DARKNESS!"
      enrage_modifier 1.3

      ability :void_nova, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 8000, type: :shadow
      end

      ability :summon_void, cooldown: 20_000 do
        spawn :add, creature_id: 51011, count: 3, spread: true
      end
    end

    on_death do
      loot_table 51001
    end
  end

  boss "Chaos Lord" do
    boss_id 51002
    health 1_200_000
    level 35
    enrage_timer 360_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "Chaos reigns eternal!"

      ability :chaos_bolt, cooldown: 6_000, target: :tank do
        damage 9000, type: :magic
      end

      ability :chaos_storm, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :purple
        damage 7000, type: :magic
      end

      ability :reality_tear, cooldown: 15_000 do
        telegraph :line, width: 5, length: 30, duration: 2000, color: :purple
        damage 8000, type: :magic
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "WITNESS TRUE CHAOS!"
      enrage_modifier 1.4

      ability :chaos_eruption, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 10000, type: :magic
      end

      ability :void_minions, cooldown: 22_000 do
        spawn :add, creature_id: 51021, count: 4, spread: true
      end

      ability :entropy, cooldown: 18_000 do
        telegraph :donut, inner_radius: 5, outer_radius: 15, duration: 2500, color: :purple
        damage 9000, type: :magic
      end
    end

    on_death do
      loot_table 51002
      achievement 5100  # Riot in the Void completion
    end
  end
end
