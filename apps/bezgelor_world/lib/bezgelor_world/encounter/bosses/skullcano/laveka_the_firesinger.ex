defmodule BezgelorWorld.Encounter.Bosses.Skullcano.LavekaTheFiresinger do
  @moduledoc """
  Laveka the Firesinger encounter - Skullcano (Final Boss)

  A powerful fire shaman who commands volcanic forces. Features:
  - Fire totems that must be killed or they empower the boss
  - Lava eruptions creating hazard zones
  - Volcanic prison requiring team coordination to free
  - Devastating Inferno room-wide in final phase

  ## Strategy
  Phase 1 (100-70%): Kill totems quickly, dodge fireballs, face Scorch away
  Phase 2 (70-30%): Priority DPS totems, avoid lava pools, use cooldowns
  Phase 3 (<30%): Stack for Volcanic Prison breaks, heal through Inferno

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Laveka the Firesinger" do
    boss_id(50203)
    health(2_200_000)
    level(30)
    enrage_timer(540_000)
    interrupt_armor(2)

    # Phase 1: 100% - 70% health - Flame Dance
    phase :one, health_above: 70 do
      phase_emote("The volcano sings! Listen to its voice!")

      ability :fireball, cooldown: 6_000, target: :random do
        telegraph(:circle, radius: 5, duration: 1200, color: :red)
        damage(5000, type: :fire)
      end

      ability :flame_totem, cooldown: 20_000 do
        spawn(:add, creature_id: 50213, count: 1)
        phase_emote("Rise, servant of flame!")
      end

      ability :scorch, cooldown: 10_000, target: :tank do
        telegraph(:cone, angle: 60, length: 15, duration: 1500, color: :red)
        damage(6000, type: :fire)
        debuff(:burning, duration: 8000, stacks: 2)
      end

      ability :flame_breath, cooldown: 12_000 do
        telegraph(:cone, angle: 45, length: 20, duration: 1800, color: :red)
        damage(7000, type: :fire)
      end

      ability :ignite, cooldown: 8_000, target: :random do
        damage(4000, type: :fire)
        debuff(:ignited, duration: 6000, stacks: 1)
      end
    end

    # Phase 2: 70% - 30% health - Volcanic Fury
    phase :two, health_between: {30, 70} do
      inherit_phase(:one)
      phase_emote("Feel the mountain's WRATH!")
      enrage_modifier(1.2)

      ability :lava_eruption, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 8, duration: 2000, color: :red)
        damage(8000, type: :fire)
        debuff(:molten, duration: 10000, stacks: 1)
      end

      ability :fire_shield, cooldown: 25_000 do
        buff(:fire_shield, duration: 10000)
        phase_emote("The flames protect me!")
      end

      ability :rain_of_fire, cooldown: 18_000 do
        telegraph(:circle, radius: 6, duration: 1500, color: :red)
        damage(5000, type: :fire)
        spawn(:add, creature_id: 50215, count: 3, spread: true)
      end

      ability :magma_wave, cooldown: 22_000 do
        telegraph(:line, width: 8, length: 30, duration: 2000, color: :red)
        damage(7000, type: :fire)
        debuff(:slowed, duration: 4000)
      end

      ability :dual_totems, cooldown: 35_000 do
        spawn(:add, creature_id: 50213, count: 2, spread: true)
      end
    end

    # Phase 3: Below 30% health - Eruption
    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("BURN! BURN IT ALL!")
      enrage_modifier(1.5)

      ability :volcanic_prison, cooldown: 30_000, target: :random do
        telegraph(:circle, radius: 4, duration: 2000, color: :purple)
        debuff(:imprisoned, duration: 5000)
        coordination(:stack, min_players: 2, damage: 15000)
      end

      ability :inferno, cooldown: 40_000 do
        telegraph(:room_wide, duration: 4000)
        damage(10000, type: :fire)
        debuff(:seared, duration: 12000, stacks: 1)
      end

      ability :empowered_totem, cooldown: 25_000 do
        spawn(:add, creature_id: 50214, count: 2, spread: true)
        phase_emote("My greatest servants, AWAKEN!")
      end

      ability :pyroclasm, cooldown: 20_000 do
        telegraph(:circle, radius: 12, duration: 2500, color: :red)
        damage(9000, type: :fire)
        movement(:knockback, distance: 8)
      end

      ability :volcanic_fissure, cooldown: 15_000 do
        telegraph(:line, width: 4, length: 40, duration: 1800, color: :red)
        damage(8000, type: :fire)
        debuff(:burning, duration: 10000, stacks: 3)
      end

      ability :meltdown, cooldown: 50_000 do
        telegraph(:room_wide, duration: 5000)
        damage(12000, type: :fire)
        buff(:meltdown, duration: 20000)
      end
    end

    on_death do
      loot_table(50203)
      # Skullcano completion
      achievement(6802)
    end
  end
end
