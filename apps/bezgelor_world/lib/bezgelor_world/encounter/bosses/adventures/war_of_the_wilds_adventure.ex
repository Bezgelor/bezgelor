defmodule BezgelorWorld.Encounter.Bosses.Adventures.WarOfTheWildsAdventure do
  @moduledoc """
  War of the Wilds Adventure bosses.
  Navigate through hostile jungle territory.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Jungle Warlord" do
    boss_id 70501
    health 2_600_000
    level 40
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "The jungle belongs to US!"

      ability :primal_strike, cooldown: 5_000, target: :tank do
        damage 14000, type: :physical
        debuff :bleeding, duration: 8000, stacks: 1
      end

      ability :spear_throw, cooldown: 12_000, target: :farthest do
        telegraph :line, width: 3, length: 30, duration: 1500, color: :brown
        damage 12000, type: :physical
      end

      ability :war_drums, cooldown: 20_000 do
        buff :war_frenzy, duration: 12000
        spawn :add, creature_id: 70511, count: 2, spread: true
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "WARRIORS! TO ME!"
      enrage_modifier 1.4

      ability :tribal_summon, cooldown: 25_000 do
        spawn :add, creature_id: 70512, count: 4, spread: true
      end

      ability :berserker_rage, cooldown: 28_000 do
        telegraph :circle, radius: 12, duration: 2000, color: :red
        damage 16000, type: :physical
        buff :enraged, duration: 10000
      end
    end

    on_death do
      loot_table 70501
    end
  end

  boss "Primal Guardian" do
    boss_id 70502
    health 3_000_000
    level 40
    enrage_timer 360_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "The jungle spirits protect this place!"

      ability :nature_strike, cooldown: 5_000, target: :tank do
        damage 15000, type: :nature
      end

      ability :entangling_vines, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :green
        damage 10000, type: :nature
        debuff :rooted, duration: 4000
      end

      ability :spirit_blast, cooldown: 15_000 do
        telegraph :cone, angle: 60, length: 22, duration: 2000, color: :green
        damage 13000, type: :nature
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "THE SPIRITS RISE!"
      enrage_modifier 1.4

      ability :summon_spirits, cooldown: 25_000 do
        spawn :add, creature_id: 70521, count: 3, spread: true
      end

      ability :nature_wrath, cooldown: 22_000 do
        telegraph :room_wide, duration: 3500
        damage 18000, type: :nature
      end
    end

    on_death do
      loot_table 70502
    end
  end

  boss "Nature's Vengeance" do
    boss_id 70503
    health 3_800_000
    level 40
    enrage_timer 420_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "You have defiled the sacred grove!"

      ability :vengeful_strike, cooldown: 5_000, target: :tank do
        damage 18000, type: :nature
        debuff :nature_vulnerability, duration: 10000, stacks: 1
      end

      ability :thorn_storm, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 8, duration: 1800, color: :green
        damage 14000, type: :nature
        coordination :spread, damage: 25000, min_distance: 6
      end

      ability :primal_wave, cooldown: 15_000 do
        telegraph :cone, angle: 90, length: 25, duration: 2000, color: :green
        damage 16000, type: :nature
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "THE JUNGLE HUNGERS!"
      enrage_modifier 1.45

      ability :spawn_treants, cooldown: 25_000 do
        spawn :add, creature_id: 70531, count: 4, spread: true
      end

      ability :overgrowth, cooldown: 22_000 do
        telegraph :donut, inner_radius: 5, outer_radius: 15, duration: 2500, color: :green
        damage 20000, type: :nature
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "NATURE RECLAIMS ALL!"
      enrage_modifier 1.8

      ability :apocalyptic_growth, cooldown: 28_000 do
        telegraph :room_wide, duration: 4000
        damage 28000, type: :nature
      end

      ability :final_vengeance, cooldown: 20_000 do
        telegraph :cross, length: 30, width: 6, duration: 2000, color: :green
        damage 24000, type: :nature
      end
    end

    on_death do
      loot_table 70503
      achievement 7050  # War of the Wilds Adventure completion
    end
  end
end
