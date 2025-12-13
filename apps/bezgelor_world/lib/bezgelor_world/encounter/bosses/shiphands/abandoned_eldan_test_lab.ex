defmodule BezgelorWorld.Encounter.Bosses.Shiphands.AbandonedEldanTestLab do
  @moduledoc """
  Abandoned Eldan Test Lab shiphand boss.
  Failed Eldan experiment with dangerous abilities.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Eldan Experiment" do
    boss_id 60801
    health 250_000
    level 48
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 60 do
      phase_emote "SYSTEMS... ONLINE... TERMINATE... INTRUDERS..."

      ability :experimental_beam, cooldown: 5_000, target: :tank do
        damage 4000, type: :magic
      end

      ability :unstable_reaction, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :blue
        damage 3500, type: :magic
        debuff :corrupted, duration: 6000, stacks: 1
      end

      ability :data_stream, cooldown: 15_000 do
        telegraph :line, width: 5, length: 25, duration: 2000, color: :blue
        damage 3800, type: :magic
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "EXPERIMENT... FAILING... COMPENSATING..."
      enrage_modifier 1.3

      ability :deploy_drones, cooldown: 25_000 do
        spawn :add, creature_id: 60811, count: 3, spread: true
      end

      ability :containment_field, cooldown: 20_000 do
        telegraph :donut, inner_radius: 4, outer_radius: 12, duration: 2500, color: :blue
        damage 4200, type: :magic
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "CRITICAL... FAILURE... MELTDOWN... IMMINENT..."
      enrage_modifier 1.5

      ability :system_overload, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 5000, type: :magic
      end

      ability :final_protocol, cooldown: 20_000 do
        telegraph :cross, length: 25, width: 5, duration: 2000, color: :red
        damage 4500, type: :magic
      end
    end

    on_death do
      loot_table 60801
      achievement 6080  # Abandoned Eldan Test Lab completion
    end
  end
end
