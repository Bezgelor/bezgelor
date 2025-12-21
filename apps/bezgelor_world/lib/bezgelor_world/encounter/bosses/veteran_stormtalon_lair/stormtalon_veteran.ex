defmodule BezgelorWorld.Encounter.Bosses.VeteranStormtalonLair.StormtalonVeteran do
  @moduledoc """
  Stormtalon (Veteran) encounter - Veteran Stormtalon's Lair (Final Boss)

  The veteran version of Stormtalon with 4 phases and complex mechanics. Features:
  - 4 distinct phases with escalating damage
  - Electrocution spread mechanic
  - Eye of Stormtalon donut mechanic
  - Mass Electrocution stack mechanic in final phase
  - Storm Elemental adds throughout

  ## Strategy
  Phase 1 (100-75%): Learn patterns, avoid Lightning Breath cone
  Phase 2 (75-50%): Spread for Electrocution, kill elementals
  Phase 3 (50-25%): Stand in Eye donut safe zone, use healing CDs for Lightning Storm
  Phase 4 (<25%): Stack for Mass Electrocution, burn before Apocalypse Storm

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon (Veteran)" do
    boss_id(50503)
    health(5_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(5)

    phase :one, health_above: 75 do
      phase_emote("SCREEEEECH! You dare enter my domain?!")

      ability :talon_strike, cooldown: 8_000, target: :tank do
        damage(25000, type: :physical)
        debuff(:talon_wound, duration: 12000, stacks: 1)
      end

      ability :static_charge, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 12, duration: 2000, color: :blue)
        damage(15000, type: :magic)
      end

      ability :lightning_breath, cooldown: 12_000 do
        telegraph(:cone, angle: 90, length: 30, duration: 2500, color: :blue)
        damage(18000, type: :magic)
      end

      ability :wing_buffet, cooldown: 18_000 do
        telegraph(:cone, angle: 120, length: 20, duration: 2000, color: :blue)
        damage(14000, type: :physical)
        movement(:knockback, distance: 12)
      end

      ability :static_field, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :blue)
        damage(12000, type: :magic)
        debuff(:static, duration: 6000, stacks: 1)
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase(:one)
      phase_emote("Lightning storms consume all who oppose me!")
      enrage_modifier(1.3)

      ability :storm_surge, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(14000, type: :magic)
        debuff(:storm_touched, duration: 10000, stacks: 1)
      end

      ability :spawn_storm_elementals, cooldown: 35_000 do
        spawn(:add, creature_id: 50532, count: 3, spread: true)
      end

      ability :electrocution, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 5, duration: 3000, color: :blue)
        coordination(:spread, min_distance: 10, damage: 16000)
      end

      ability :thunder_clap, cooldown: 20_000 do
        telegraph(:circle, radius: 18, duration: 2500, color: :blue)
        damage(14000, type: :magic)
        movement(:knockback, distance: 8)
      end

      ability :charged_feathers, cooldown: 28_000 do
        telegraph(:cone, angle: 180, length: 25, duration: 3000, color: :blue)
        damage(16000, type: :magic)
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase(:two)
      phase_emote("THE STORM AWAKENS! FEEL TRUE POWER!")
      enrage_modifier(1.5)

      ability :thunder_god, cooldown: 45_000 do
        buff(:thunder_god, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end

      ability :lightning_storm, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4500)
        damage(18000, type: :magic)
        debuff(:electrified, duration: 12000, stacks: 2)
      end

      ability :eye_of_stormtalon, cooldown: 30_000 do
        telegraph(:donut, inner_radius: 8, outer_radius: 25, duration: 4000, color: :blue)
        damage(20000, type: :magic)
      end

      ability :storm_dive, cooldown: 22_000, target: :farthest do
        telegraph(:line, width: 8, length: 40, duration: 2000, color: :blue)
        damage(18000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :elemental_fury, cooldown: 40_000 do
        spawn(:add, creature_id: 50532, count: 4, spread: true)
        telegraph(:room_wide, duration: 2000)
        damage(10000, type: :magic)
      end
    end

    phase :four, health_below: 25 do
      inherit_phase(:three)
      phase_emote("I WILL REDUCE YOU TO ASH!")
      enrage_modifier(1.8)

      ability :apocalypse_storm, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(22000, type: :magic)
        debuff(:apocalypse, duration: 15000, stacks: 2)
      end

      ability :final_thunder, cooldown: 35_000 do
        telegraph(:circle, radius: 25, duration: 4000, color: :blue)
        damage(25000, type: :magic)
        movement(:knockback, distance: 12, source: :center)
      end

      ability :mass_electrocution, cooldown: 40_000, target: :random do
        telegraph(:circle, radius: 8, duration: 4000, color: :blue)
        coordination(:stack, min_players: 5, damage: 60000)
      end

      ability :divine_storm, cooldown: 45_000 do
        telegraph(:cross, length: 40, width: 10, duration: 3500, color: :blue)
        damage(20000, type: :magic)
        spawn(:add, creature_id: 50532, count: 2, spread: true)
      end

      ability :storm_avatar, cooldown: 60_000 do
        buff(:storm_avatar, duration: 20000)
        buff(:damage_increase, duration: 20000)
        telegraph(:room_wide, duration: 3000)
        damage(15000, type: :magic)
      end
    end

    on_death do
      loot_table(50503)
      # Veteran Stormtalon's Lair completion
      achievement(5050)
    end
  end
end
