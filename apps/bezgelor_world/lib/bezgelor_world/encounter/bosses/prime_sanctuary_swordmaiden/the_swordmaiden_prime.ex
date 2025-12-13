defmodule BezgelorWorld.Encounter.Bosses.PrimeSanctuarySwordmaiden.TheSwordmaidenPrime do
  @moduledoc """
  The Swordmaiden (Prime) - Final boss of Prime SSM.
  The ultimate 5-phase challenge with devastating sword techniques.
  """

  use BezgelorWorld.Encounter.DSL

  boss "The Swordmaiden (Prime)" do
    boss_id 14105
    health 20_000_000
    level 50
    enrage_timer 720_000
    interrupt_armor 6

    phase :one, health_above: 80 do
      phase_emote "You seek to challenge the Swordmaiden? Prepare yourself!"

      ability :blade_dance, cooldown: 5_000, target: :tank do
        damage 45000, type: :physical
        debuff :bleeding, duration: 10000, stacks: 2
      end

      ability :sword_arc, cooldown: 10_000 do
        telegraph :cone, angle: 120, length: 20, duration: 1800, color: :red
        damage 35000, type: :physical
      end

      ability :whirlwind, cooldown: 15_000 do
        telegraph :circle, radius: 12, duration: 2000, color: :red
        damage 38000, type: :physical
        movement :knockback, distance: 8
      end
    end

    phase :two, health_between: [60, 80] do
      inherit_phase :one
      phase_emote "Your technique is... adequate. Let me show you mine!"
      enrage_modifier 1.25

      ability :tempest_strike, cooldown: 12_000 do
        telegraph :cross, length: 28, width: 5, duration: 2000, color: :red
        damage 42000, type: :physical
      end

      ability :blade_storm, cooldown: 20_000 do
        telegraph :room_wide, duration: 3000
        damage 40000, type: :physical
        coordination :spread, damage: 65000, min_distance: 8
      end
    end

    phase :three, health_between: [40, 60] do
      inherit_phase :two
      phase_emote "IMPRESSIVE! But can you handle this?!"
      enrage_modifier 1.45

      ability :summon_blade_spirits, cooldown: 30_000 do
        spawn :add, creature_id: 14151, count: 4, spread: true
      end

      ability :thousand_cuts, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 6, duration: 1500, color: :red
        damage 50000, type: :physical
        coordination :spread, damage: 80000, min_distance: 10
      end

      ability :blade_barrier, cooldown: 25_000 do
        buff :blade_barrier, duration: 10000
        buff :damage_reflection, duration: 10000
      end
    end

    phase :four, health_between: [20, 40] do
      inherit_phase :three
      phase_emote "YOU HAVE PUSHED ME TO MY LIMITS! WITNESS MY TRUE POWER!"
      enrage_modifier 1.7

      ability :final_dance, cooldown: 22_000 do
        telegraph :room_wide, duration: 4000
        damage 60000, type: :physical
      end

      ability :execution_strike, cooldown: 18_000, target: :lowest_health do
        telegraph :line, width: 4, length: 30, duration: 1500, color: :red
        damage 70000, type: :physical
      end

      ability :blade_domain, cooldown: 28_000 do
        telegraph :donut, inner_radius: 8, outer_radius: 20, duration: 2500, color: :red
        damage 55000, type: :physical
      end
    end

    phase :five, health_below: 20 do
      inherit_phase :four
      phase_emote "THE SWORDMAIDEN BOWS TO NO ONE! PREPARE FOR YOUR END!"
      enrage_modifier 2.0

      ability :apocalyptic_blade, cooldown: 30_000 do
        telegraph :room_wide, duration: 5000
        damage 85000, type: :physical
      end

      ability :avatar_of_blades, cooldown: 25_000 do
        buff :avatar_of_blades, duration: 20000
        buff :damage_increase, duration: 20000
        buff :speed_increase, duration: 20000
      end

      ability :final_judgment, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :red
        coordination :stack, damage: 120000, required_players: 4
      end

      ability :blade_apocalypse, cooldown: 35_000 do
        telegraph :cross, length: 40, width: 8, duration: 2500, color: :red
        damage 75000, type: :physical
        spawn :add, creature_id: 14152, count: 6, spread: true
      end
    end

    on_death do
      loot_table 14105
      achievement 1410  # Prime Sanctuary of the Swordmaiden completion
    end
  end
end
