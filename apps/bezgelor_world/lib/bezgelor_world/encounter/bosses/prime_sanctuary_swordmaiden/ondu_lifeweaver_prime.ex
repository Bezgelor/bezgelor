defmodule BezgelorWorld.Encounter.Bosses.PrimeSanctuarySwordmaiden.OnduLifeweaverPrime do
  @moduledoc """
  Ondu Lifeweaver (Prime) - Second boss of Prime SSM.
  Nature shaman with healing and nature damage.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Ondu Lifeweaver (Prime)" do
    boss_id 14102
    health 9_000_000
    level 50
    enrage_timer 360_000
    interrupt_armor 4

    phase :one, health_above: 60 do
      phase_emote "Nature protects its children!"

      ability :thorn_strike, cooldown: 5_000, target: :tank do
        damage 32000, type: :nature
        debuff :bleeding, duration: 10000, stacks: 2
      end

      ability :entangling_roots, cooldown: 10_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :green
        damage 25000, type: :nature
        debuff :rooted, duration: 4000
      end

      ability :nature_blast, cooldown: 15_000 do
        telegraph :cone, angle: 60, length: 24, duration: 2000, color: :green
        damage 30000, type: :nature
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "THE FOREST RISES!"
      enrage_modifier 1.4

      ability :summon_treants, cooldown: 25_000 do
        spawn :add, creature_id: 14121, count: 3, spread: true
      end

      ability :rejuvenation, cooldown: 30_000 do
        buff :regeneration, duration: 15000
        buff :healing, duration: 15000
      end

      ability :seed_storm, cooldown: 20_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :green
        damage 35000, type: :nature
        spawn :add, creature_id: 14122, count: 4, spread: true
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "NATURE'S WRATH IS ABSOLUTE!"
      enrage_modifier 1.7

      ability :forest_fury, cooldown: 28_000 do
        telegraph :room_wide, duration: 4000
        damage 48000, type: :nature
      end

      ability :thorn_cross, cooldown: 18_000 do
        telegraph :cross, length: 30, width: 5, duration: 2000, color: :green
        damage 42000, type: :nature
      end
    end

    on_death do
      loot_table 14102
    end
  end
end
