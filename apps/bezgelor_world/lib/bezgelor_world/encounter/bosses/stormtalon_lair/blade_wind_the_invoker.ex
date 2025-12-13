defmodule BezgelorWorld.Encounter.Bosses.StormtalonLair.BladeWindTheInvoker do
  @moduledoc """
  Blade-Wind the Invoker - Second boss of Stormtalon's Lair (Normal).
  Pell shaman with lightning and thunder magic.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Blade-Wind the Invoker" do
    boss_id 10102
    health 600_000
    level 21
    enrage_timer 240_000
    interrupt_armor 1

    phase :one, health_above: 40 do
      phase_emote "The spirits guide my blade!"

      ability :lightning_strike, cooldown: 6_000, target: :tank do
        damage 4000, type: :magic
      end

      ability :thunder_call, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1500, color: :blue
        damage 3200, type: :magic
      end

      ability :static_discharge, cooldown: 15_000 do
        telegraph :cone, angle: 45, length: 18, duration: 1800, color: :blue
        damage 3500, type: :magic
      end
    end

    phase :two, health_below: 40 do
      inherit_phase :one
      phase_emote "SPIRITS OF THE STORM, AID ME!"
      enrage_modifier 1.25

      ability :summon_elementals, cooldown: 25_000 do
        spawn :add, creature_id: 10112, count: 2, spread: true
      end

      ability :chain_lightning, cooldown: 18_000 do
        telegraph :line, width: 3, length: 25, duration: 1800, color: :blue
        damage 4000, type: :magic
      end
    end

    on_death do
      loot_table 10102
    end
  end
end
