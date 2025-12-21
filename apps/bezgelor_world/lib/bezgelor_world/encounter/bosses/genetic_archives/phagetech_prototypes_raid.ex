defmodule BezgelorWorld.Encounter.Bosses.GeneticArchives.PhagetechPrototypesRaid do
  @moduledoc """
  Phagetech Prototypes encounter - Genetic Archives (Third Boss - 20-man Raid)

  Two prototype constructs that share health and abilities. Features:
  - Alpha Strike tank buster
  - Beta Beam line AoE
  - Synchronize phase where both must die together
  - Combined Assault room-wide when synced

  ## Strategy
  Phase 1 (100-60%): Split raid between both prototypes, balance damage
  Phase 2 (<60%): Must kill within 10% health of each other or they heal

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Phagetech Prototypes" do
    boss_id(60003)
    health(40_000_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("PROTOTYPE ALPHA ONLINE. PROTOTYPE BETA ONLINE. INITIATING COMBAT PROTOCOLS.")

      ability :prototype_alpha_strike, cooldown: 10_000, target: :tank do
        damage(45000, type: :physical)
        debuff(:armor_shred, duration: 10000, stacks: 1)
      end

      ability :prototype_beta_beam, cooldown: 15_000 do
        telegraph(:line, width: 6, length: 40, duration: 2500, color: :blue)
        damage(35000, type: :magic)
      end

      ability :alpha_charge, cooldown: 20_000, target: :farthest do
        telegraph(:line, width: 5, length: 35, duration: 2000, color: :red)
        damage(30000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :beta_pulse, cooldown: 18_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :blue)
        damage(25000, type: :magic)
        debuff(:slowed, duration: 4000)
      end

      ability :targeting_laser, cooldown: 8_000, target: :random do
        telegraph(:line, width: 3, length: 30, duration: 1500, color: :red)
        damage(20000, type: :fire)
      end
    end

    phase :two, health_below: 60 do
      inherit_phase(:one)
      phase_emote("SYNCHRONIZATION PROTOCOL ENGAGED. COMBINING ASSAULT PATTERNS.")
      enrage_modifier(1.4)

      ability :synchronize, cooldown: 40_000 do
        buff(:synchronized, duration: 20000)
        telegraph(:room_wide, duration: 3000)
      end

      ability :combined_assault, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(40000, type: :physical)
        damage(40000, type: :magic)
      end

      ability :dual_beam, cooldown: 25_000 do
        telegraph(:cross, length: 35, width: 6, duration: 3000, color: :purple)
        damage(45000, type: :magic)
      end

      ability :overcharge, cooldown: 35_000 do
        buff(:overcharged, duration: 15000)
        telegraph(:circle, radius: 20, duration: 4000, color: :red)
        damage(35000, type: :fire)
      end

      ability :prototype_rage, cooldown: 45_000 do
        buff(:enraged, duration: 20000)
        spawn(:add, creature_id: 60031, count: 4, spread: true)
      end

      ability :system_failure, cooldown: 60_000 do
        telegraph(:room_wide, duration: 5000)
        damage(50000, type: :magic)
        debuff(:system_shocked, duration: 8000, stacks: 1)
      end
    end

    on_death do
      loot_table(60003)
    end
  end
end
