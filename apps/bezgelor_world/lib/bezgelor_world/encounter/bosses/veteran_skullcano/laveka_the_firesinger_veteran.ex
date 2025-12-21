defmodule BezgelorWorld.Encounter.Bosses.VeteranSkullcano.LavekaTheFiresingerVeteran do
  @moduledoc """
  Laveka the Firesinger (Veteran) encounter - Veteran Skullcano (Final Boss)

  The veteran version of Laveka with 3 intense fire phases. Features:
  - Fire totem adds throughout
  - Lava Wave line attack
  - Volcanic Apocalypse room-wide wipe mechanic
  - Final Song stack mechanic

  ## Strategy
  Phase 1 (100-70%): Kill fire totems, avoid Searing Breath cone
  Phase 2 (70-40%): Dodge Lava Wave, survive Eruption with healing CDs
  Phase 3 (<40%): Stack for Final Song, burn before Volcanic Apocalypse

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Laveka the Firesinger (Veteran)" do
    boss_id(50703)
    health(5_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(5)

    phase :one, health_above: 70 do
      phase_emote("The volcano sings my song of destruction!")

      ability :flame_bolt, cooldown: 10_000 do
        telegraph(:line, width: 5, length: 30, duration: 2000, color: :red)
        damage(16000, type: :fire)
      end

      ability :volcanic_burst, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 12, duration: 2000, color: :red)
        damage(18000, type: :fire)
      end

      ability :fire_totem, cooldown: 25_000 do
        spawn(:add, creature_id: 50732, count: 2, spread: true)
      end

      ability :searing_breath, cooldown: 18_000 do
        telegraph(:cone, angle: 90, length: 25, duration: 2500, color: :red)
        damage(20000, type: :fire)
        debuff(:seared, duration: 10000, stacks: 1)
      end

      ability :fire_whip, cooldown: 12_000, target: :tank do
        damage(22000, type: :fire)
        debuff(:burning, duration: 8000, stacks: 1)
      end
    end

    phase :two, health_between: {40, 70} do
      inherit_phase(:one)
      phase_emote("Feel the volcano's fury!")
      enrage_modifier(1.35)

      ability :eruption, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(16000, type: :fire)
        debuff(:erupted, duration: 12000, stacks: 1)
      end

      ability :lava_wave, cooldown: 20_000 do
        telegraph(:line, width: 10, length: 40, duration: 3000, color: :red)
        damage(20000, type: :fire)
        movement(:knockback, distance: 12)
      end

      ability :fire_dance, cooldown: 35_000 do
        buff(:fire_dancing, duration: 10000)
        buff(:damage_increase, duration: 10000)
      end

      ability :magma_spray, cooldown: 22_000, target: :random do
        telegraph(:cone, angle: 120, length: 30, duration: 2500, color: :red)
        damage(18000, type: :fire)
      end

      ability :infernal_totems, cooldown: 32_000 do
        spawn(:add, creature_id: 50732, count: 3, spread: true)
        telegraph(:room_wide, duration: 2000)
        damage(8000, type: :fire)
      end
    end

    phase :three, health_below: 40 do
      inherit_phase(:two)
      phase_emote("BURN IN THE VOLCANO'S EMBRACE!")
      enrage_modifier(1.6)

      ability :volcanic_apocalypse, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(22000, type: :fire)
        debuff(:volcanic_doom, duration: 20000, stacks: 2)
      end

      ability :magma_pool, cooldown: 25_000 do
        telegraph(:circle, radius: 20, duration: 3500, color: :red)
        damage(25000, type: :fire)
        movement(:pull, distance: 10)
      end

      ability :final_song, cooldown: 40_000, target: :random do
        telegraph(:circle, radius: 8, duration: 4000, color: :red)
        coordination(:stack, min_players: 5, damage: 75000)
      end

      ability :fire_nova, cooldown: 22_000 do
        telegraph(:circle, radius: 18, duration: 2500, color: :red)
        damage(20000, type: :fire)
        movement(:knockback, distance: 12, source: :center)
      end

      ability :ultimate_firesong, cooldown: 50_000 do
        buff(:firesong, duration: 20000)
        buff(:damage_increase, duration: 20000)
        spawn(:add, creature_id: 50732, count: 4, spread: true)
        telegraph(:room_wide, duration: 3000)
        damage(15000, type: :fire)
      end
    end

    on_death do
      loot_table(50703)
      # Veteran Skullcano completion
      achievement(5070)
    end
  end
end
