defmodule BezgelorWorld.Encounter.Bosses.Datascape.GloomclawRaid do
  @moduledoc """
  Gloomclaw encounter - Datascape (Second Boss - 40-man Raid)

  A massive shadow creature dwelling in the depths of the Datascape. Features:
  - Shadow damage throughout with stacking debuffs
  - Terror Spawn adds that fear players
  - Eclipse room-wide requiring healing cooldowns
  - Shadow Rift portals spawning additional threats

  ## Strategy
  Phase 1 (100-65%): Manage terror adds, avoid shadow beams
  Phase 2 (65-35%): Handle Eclipse with healing CDs, destroy portals
  Phase 3 (<35%): Burn through Void Eruption, dispel Lightless stacks

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Gloomclaw" do
    boss_id(70002)
    health(140_000_000)
    level(50)
    enrage_timer(960_000)
    interrupt_armor(7)

    phase :one, health_above: 65 do
      phase_emote("The darkness shall consume you all!")

      ability :shadow_slash, cooldown: 8_000, target: :tank do
        damage(70000, type: :shadow)
        debuff(:shadow_wound, duration: 12000, stacks: 1)
      end

      ability :creeping_darkness, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 12, duration: 2000, color: :purple)
        damage(45000, type: :shadow)
        debuff(:creeping_dark, duration: 8000, stacks: 1)
      end

      ability :gloom_beam, cooldown: 18_000 do
        telegraph(:line, width: 6, length: 45, duration: 2500, color: :purple)
        damage(55000, type: :shadow)
      end

      ability :terror_spawn, cooldown: 35_000 do
        spawn(:add, creature_id: 70022, count: 3, spread: true)
      end

      ability :shadow_pulse, cooldown: 15_000 do
        telegraph(:circle, radius: 15, duration: 1500, color: :purple)
        damage(35000, type: :shadow)
      end
    end

    phase :two, health_between: {35, 65} do
      inherit_phase(:one)
      phase_emote("Cower before the shadow!")
      enrage_modifier(1.25)

      ability :eclipse, cooldown: 45_000 do
        telegraph(:room_wide, duration: 5000)
        damage(50000, type: :shadow)
        debuff(:eclipsed, duration: 15000, stacks: 1)
      end

      ability :fear_pulse, cooldown: 20_000 do
        telegraph(:circle, radius: 20, duration: 2000, color: :purple)
        damage(40000, type: :shadow)
        movement(:knockback, distance: 15)
      end

      ability :shadow_rift, cooldown: 40_000 do
        spawn(:add, creature_id: 70023, count: 2, spread: true)
        telegraph(:circle, radius: 10, duration: 3000, color: :purple)
      end

      ability :dark_tendrils, cooldown: 25_000, target: :random do
        telegraph(:cone, angle: 60, length: 30, duration: 2500, color: :purple)
        damage(48000, type: :shadow)
        debuff(:entangled, duration: 4000)
      end

      ability :nightmare_grasp, cooldown: 30_000, target: :random do
        telegraph(:circle, radius: 6, duration: 2000, color: :purple)
        coordination(:spread, min_distance: 8, damage: 60000)
      end
    end

    phase :three, health_below: 35 do
      inherit_phase(:two)
      phase_emote("EMBRACE THE VOID!")
      enrage_modifier(1.5)

      ability :void_eruption, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(65000, type: :shadow)
        debuff(:void_touched, duration: 20000, stacks: 1)
      end

      ability :consume_light, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 8, duration: 2500, color: :purple)
        debuff(:lightless, duration: 20000, stacks: 3)
        damage(30000, type: :shadow)
      end

      ability :annihilation, cooldown: 50_000 do
        telegraph(:room_wide, duration: 6000)
        damage(90000, type: :shadow)
      end

      ability :shadow_nova, cooldown: 22_000 do
        telegraph(:circle, radius: 25, duration: 3000, color: :purple)
        damage(55000, type: :shadow)
        movement(:knockback, distance: 10, source: :center)
      end

      ability :final_darkness, cooldown: 60_000 do
        buff(:shadow_form, duration: 20000)
        buff(:damage_increase, duration: 20000)
        spawn(:add, creature_id: 70022, count: 5, spread: true)
      end
    end

    on_death do
      loot_table(70002)
      # Datascape: Gloomclaw
      achievement(7002)
    end
  end
end
