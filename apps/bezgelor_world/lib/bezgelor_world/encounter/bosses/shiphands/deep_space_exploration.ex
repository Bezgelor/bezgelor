defmodule BezgelorWorld.Encounter.Bosses.Shiphands.DeepSpaceExploration do
  @moduledoc """
  Deep Space Exploration shiphand boss.
  Void anomaly with space-themed mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Void Anomaly" do
    boss_id 60201
    health 55_000
    level 14
    enrage_timer 120_000
    interrupt_armor 0

    phase :one, health_above: 30 do
      phase_emote "*distorted static*"

      ability :anomaly_pulse, cooldown: 5_000, target: :tank do
        damage 900, type: :magic
      end

      ability :gravity_well, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 5, duration: 1800, color: :blue
        damage 700, type: :magic
        movement :pull, distance: 3
      end

      ability :space_debris, cooldown: 15_000 do
        telegraph :line, width: 3, length: 15, duration: 1500, color: :blue
        damage 800, type: :physical
      end
    end

    phase :two, health_below: 30 do
      inherit_phase :one
      phase_emote "*reality warping*"
      enrage_modifier 1.25

      ability :dimensional_rift, cooldown: 20_000 do
        telegraph :donut, inner_radius: 2, outer_radius: 8, duration: 2000, color: :purple
        damage 1000, type: :magic
      end
    end

    on_death do
      loot_table 60201
    end
  end
end
