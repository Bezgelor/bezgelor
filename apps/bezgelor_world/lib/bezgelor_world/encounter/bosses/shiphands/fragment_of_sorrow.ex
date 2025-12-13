defmodule BezgelorWorld.Encounter.Bosses.Shiphands.FragmentOfSorrow do
  @moduledoc """
  Fragment of Sorrow shiphand boss.
  Solo-friendly encounter with moderate mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Sorrow Guardian" do
    boss_id 60101
    health 50_000
    level 12
    enrage_timer 120_000
    interrupt_armor 0

    phase :one, health_above: 30 do
      phase_emote "Protect... the fragment..."

      ability :sorrow_strike, cooldown: 5_000, target: :tank do
        damage 800, type: :shadow
      end

      ability :tear_pool, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 4, duration: 1500, color: :purple
        damage 600, type: :shadow
      end
    end

    phase :two, health_below: 30 do
      inherit_phase :one
      phase_emote "The sorrow... consumes..."
      enrage_modifier 1.2

      ability :wail_of_despair, cooldown: 18_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :purple
        damage 900, type: :shadow
      end
    end

    on_death do
      loot_table 60101
    end
  end
end
