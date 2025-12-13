defmodule BezgelorWorld.Encounter.Bosses.SanctuaryOfTheSwordmaiden.TheSwordmaiden do
  @moduledoc """
  The Swordmaiden encounter - Sanctuary of the Swordmaiden (Final Boss)

  The legendary warrior who guards the sanctuary. Features:
  - Blade Dance frontal cleave
  - Whirlwind Strike circular AoE
  - Summon Swords adds that must be killed
  - Holy Ground safe zone mechanic
  - Divine Wrath enrage phase

  ## Strategy
  Phase 1 (100-70%): Tank faces away for Blade Dance, dodge Whirlwind
  Phase 2 (70-40%): Kill sword adds quickly, use Blessing of Steel immunity
  Phase 3 (40-15%): Stay in Holy Ground safe zone, burn adds
  Phase 4 (<15%): Burn boss before Divine Wrath kills group

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "The Swordmaiden" do
    boss_id 50305
    health 2_500_000
    level 35
    enrage_timer 600_000
    interrupt_armor 3

    phase :one, health_above: 70 do
      phase_emote "You dare defile this sacred place? Face my blade!"

      ability :blade_dance, cooldown: 10_000 do
        telegraph :cone, angle: 120, length: 15, duration: 2000, color: :red
        damage 7000, type: :physical
      end

      ability :whirlwind_strike, cooldown: 18_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :red
        damage 6000, type: :physical
      end

      ability :thrust, cooldown: 6_000, target: :tank do
        telegraph :line, width: 3, length: 15, duration: 1200, color: :red
        damage 8000, type: :physical
        debuff :bleeding, duration: 6000, stacks: 1
      end

      ability :parry_riposte, cooldown: 12_000, target: :tank do
        damage 6000, type: :physical
        buff :parrying, duration: 3000
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase :one
      phase_emote "My blades shall be your end!"
      enrage_modifier 1.2

      ability :summon_swords, cooldown: 30_000 do
        spawn :add, creature_id: 50316, count: 3, spread: true
      end

      ability :blessing_of_steel, cooldown: 40_000 do
        buff :steel_blessing, duration: 15000
        telegraph :circle, radius: 8, duration: 15000, color: :blue
      end

      ability :cross_slash, cooldown: 15_000 do
        telegraph :cross, length: 20, width: 4, duration: 2000, color: :red
        damage 8000, type: :physical
      end

      ability :dancing_blade, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 6, duration: 1500, color: :red
        damage 6000, type: :physical
        movement :knockback, distance: 8
      end
    end

    phase :three, health_between: {15, 40} do
      inherit_phase :two
      phase_emote "The sanctuary shall NOT fall!"
      enrage_modifier 1.4

      ability :maidens_fury, cooldown: 12_000 do
        telegraph :circle, radius: 6, duration: 1500, color: :red
        damage 7000, type: :physical
        spawn :add, creature_id: 50316, count: 2, spread: true
      end

      ability :holy_ground, cooldown: 35_000 do
        telegraph :donut, inner_radius: 8, outer_radius: 20, duration: 3000, color: :red
        damage 10000, type: :physical
      end

      ability :blade_storm, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 6000, type: :physical
        debuff :bleeding, duration: 8000, stacks: 2
      end

      ability :executioners_strike, cooldown: 18_000, target: :lowest_health do
        telegraph :circle, radius: 5, duration: 1500, color: :red
        damage 12000, type: :physical
      end
    end

    phase :four, health_below: 15 do
      inherit_phase :three
      phase_emote "BY THE SWORD I SHALL PREVAIL!"
      enrage_modifier 1.6

      ability :final_judgment, cooldown: 45_000 do
        buff :enraged, duration: 30000
        buff :final_stand, duration: 30000
      end

      ability :divine_wrath, cooldown: 15_000 do
        telegraph :room_wide, duration: 4000
        damage 8000, type: :physical
      end

      ability :thousand_blades, cooldown: 20_000 do
        telegraph :circle, radius: 15, duration: 3000, color: :red
        damage 10000, type: :physical
        spawn :add, creature_id: 50316, count: 5, spread: true
      end

      ability :judgment_slash, cooldown: 10_000 do
        telegraph :cross, length: 25, width: 5, duration: 1800, color: :red
        damage 12000, type: :physical
      end
    end

    on_death do
      loot_table 50305
      achievement 6803  # Sanctuary of the Swordmaiden completion
    end
  end
end
