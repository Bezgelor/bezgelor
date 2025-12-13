defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.Grendelus do
  @moduledoc """
  Grendelus the Guardian - World Boss in Farside.
  Eldan construct guardian requiring 20+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Grendelus the Guardian" do
    boss_id 80004
    health 75_000_000
    level 40
    enrage_timer 900_000
    interrupt_armor 7

    phase :one, health_above: 70 do
      phase_emote "INTRUDERS DETECTED. INITIATING GUARDIAN PROTOCOLS."

      ability :guardian_strike, cooldown: 5_000, target: :tank do
        damage 58000, type: :magic
        debuff :corrupted, duration: 12000, stacks: 1
      end

      ability :data_beam, cooldown: 10_000, target: :random do
        telegraph :line, width: 8, length: 45, duration: 2000, color: :blue
        damage 45000, type: :magic
        coordination :spread, damage: 75000, min_distance: 10
      end

      ability :defense_matrix, cooldown: 20_000 do
        telegraph :donut, inner_radius: 10, outer_radius: 25, duration: 3000, color: :blue
        damage 42000, type: :magic
      end

      ability :deploy_sentinels, cooldown: 30_000 do
        spawn :add, creature_id: 80041, count: 6, spread: true
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase :one
      phase_emote "INCREASING DEFENSIVE MEASURES."
      enrage_modifier 1.35

      ability :override_protocol, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 55000, type: :magic
      end

      ability :system_purge, cooldown: 25_000 do
        telegraph :cross, length: 40, width: 10, duration: 2500, color: :blue
        damage 48000, type: :magic
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "MAXIMUM THREAT. INITIATING FINAL DEFENSE."
      enrage_modifier 1.6

      ability :apocalypse_protocol, cooldown: 40_000 do
        telegraph :room_wide, duration: 6000
        damage 75000, type: :magic
      end

      ability :guardian_overload, cooldown: 30_000 do
        buff :overloaded, duration: 20000
        buff :damage_increase, duration: 20000
        spawn :add, creature_id: 80042, count: 8, spread: true
      end
    end

    on_death do
      loot_table 80004
      achievement 8004  # Grendelus Slayer
    end
  end
end
