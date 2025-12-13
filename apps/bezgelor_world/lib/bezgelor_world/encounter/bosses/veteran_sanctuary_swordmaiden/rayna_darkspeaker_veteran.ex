defmodule BezgelorWorld.Encounter.Bosses.VeteranSanctuarySwordmaiden.RaynaDarkspeakerVeteran do
  @moduledoc """
  Rayna Darkspeaker (Veteran) - Veteran Sanctuary of the Swordmaiden (First Boss)

  Enhanced shadow-themed encounter with spread mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Rayna Darkspeaker (Veteran)" do
    boss_id 50801
    health 3_600_000
    level 50
    enrage_timer 480_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "The shadows hunger for your souls!"

      ability :dark_bolt, cooldown: 8_000, target: :tank do
        damage 18000, type: :shadow
        debuff :shadow_touched, duration: 10000, stacks: 1
      end

      ability :shadow_void, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :purple
        damage 14000, type: :shadow
      end

      ability :whispers_of_darkness, cooldown: 18_000 do
        telegraph :cone, angle: 90, length: 25, duration: 2500, color: :purple
        damage 16000, type: :shadow
        debuff :maddened, duration: 6000
      end

      ability :summon_shades, cooldown: 25_000 do
        spawn :add, creature_id: 50812, count: 3, spread: true
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "EMBRACE THE DARKNESS!"
      enrage_modifier 1.4

      ability :shadow_nova, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 14000, type: :shadow
        debuff :darkness, duration: 12000, stacks: 1
      end

      ability :dark_tether, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 5, duration: 3000, color: :purple
        coordination :spread, min_distance: 10, damage: 16000
      end

      ability :soul_rend, cooldown: 30_000 do
        telegraph :cross, length: 30, width: 6, duration: 2500, color: :purple
        damage 18000, type: :shadow
      end
    end

    on_death do
      loot_table 50801
    end
  end
end
