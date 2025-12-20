defmodule BezgelorWorld.Encounter.Bosses.VeteranSkullcano.ThunderfootVeteran do
  @moduledoc """
  Thunderfoot (Veteran) encounter - Veteran Skullcano (Second Boss)

  The veteran version of Thunderfoot with enhanced seismic mechanics. Features:
  - 3-phase fight with Stampede spread mechanic
  - Earthquake room-wide damage
  - Pack adds in phase 2
  - Ultimate Stomp wipe mechanic in phase 3

  ## Strategy
  Phase 1 (100-60%): Spread for Stampede, avoid Gore Charge line
  Phase 2 (60-30%): Kill pack adds, survive Earthquake
  Phase 3 (<30%): Burn through Ultimate Stomp, use healing CDs

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Thunderfoot (Veteran)" do
    boss_id(50702)
    health(4_000_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("THUNDERFOOT CRUSH!")

      ability :seismic_stomp, cooldown: 12_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :brown)
        damage(16000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :gore_charge, cooldown: 15_000, target: :farthest do
        telegraph(:line, width: 6, length: 35, duration: 2500, color: :brown)
        damage(14000, type: :physical)
        movement(:knockback, distance: 12)
      end

      ability :thunder_strike, cooldown: 10_000, target: :tank do
        damage(22000, type: :physical)
        debuff(:thunder_struck, duration: 10000, stacks: 1)
      end

      ability :stampede, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 5, duration: 3000, color: :brown)
        coordination(:spread, min_distance: 8, damage: 15000)
      end

      ability :ground_slam, cooldown: 18_000 do
        telegraph(:cone, angle: 90, length: 25, duration: 2000, color: :brown)
        damage(14000, type: :physical)
      end
    end

    phase :two, health_between: {30, 60} do
      inherit_phase(:one)
      phase_emote("THE GROUND SHAKES!")
      enrage_modifier(1.35)

      ability :earthquake, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(14000, type: :physical)
        debuff(:shaken, duration: 10000, stacks: 1)
      end

      ability :boulder_throw, cooldown: 18_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :brown)
        damage(18000, type: :physical)
      end

      ability :summon_pack, cooldown: 30_000 do
        spawn(:add, creature_id: 50722, count: 4, spread: true)
      end

      ability :tremor, cooldown: 22_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 18, duration: 2500, color: :brown)
        damage(16000, type: :physical)
      end

      ability :horn_toss, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 6, duration: 1800, color: :brown)
        damage(14000, type: :physical)
        movement(:knockback, distance: 15)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("THUNDERFOOT RAGE!")
      enrage_modifier(1.6)

      ability :ultimate_stomp, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(20000, type: :physical)
        debuff(:devastated, duration: 15000, stacks: 2)
      end

      ability :primal_fury, cooldown: 40_000 do
        buff(:primal_fury, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end

      ability :fissure, cooldown: 20_000 do
        telegraph(:line, width: 8, length: 40, duration: 3000, color: :brown)
        damage(22000, type: :physical)
      end

      ability :earth_shatter, cooldown: 25_000 do
        telegraph(:cross, length: 35, width: 8, duration: 2500, color: :brown)
        damage(18000, type: :physical)
        spawn(:add, creature_id: 50722, count: 2, spread: true)
      end

      ability :final_rampage, cooldown: 45_000 do
        buff(:rampaging, duration: 20000)
        telegraph(:room_wide, duration: 3000)
        damage(15000, type: :physical)
      end
    end

    on_death do
      loot_table(50702)
    end
  end
end
