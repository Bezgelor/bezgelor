defmodule BezgelorWorld.Encounter.Bosses.VeteranKelVoreth.ForgemasterTrogunVeteran do
  @moduledoc """
  Forgemaster Trogun (Veteran) encounter - Veteran Kel Voreth (Final Boss)

  The veteran version of Trogun with 4 complex phases. Features:
  - Fire-themed damage throughout
  - Construct adds that must be tanked
  - Molten Core stack mechanic in final phase
  - Apocalypse Forge room-wide wipe mechanic

  ## Strategy
  Phase 1 (100-75%): Avoid Molten Slag, heal through Heat Wave
  Phase 2 (75-50%): Kill Constructs, burn Tempered Steel buff
  Phase 3 (50-25%): Survive Volcanic Eruption, avoid Lava Pools
  Phase 4 (<25%): Stack for Molten Core, burn before Apocalypse Forge

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Forgemaster Trogun (Veteran)" do
    boss_id 50603
    health 5_500_000
    level 50
    enrage_timer 600_000
    interrupt_armor 5

    phase :one, health_above: 75 do
      phase_emote "The forge burns eternal!"

      ability :forge_hammer, cooldown: 8_000, target: :tank do
        damage 28000, type: :physical
        debuff :hammered, duration: 10000, stacks: 1
      end

      ability :molten_slag, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :red
        damage 16000, type: :fire
        debuff :slagged, duration: 8000, stacks: 1
      end

      ability :heat_wave, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 12000, type: :fire
        debuff :overheated, duration: 10000, stacks: 1
      end

      ability :anvil_strike, cooldown: 15_000 do
        telegraph :cone, angle: 90, length: 25, duration: 2500, color: :red
        damage 18000, type: :physical
        movement :knockback, distance: 8
      end

      ability :spark_shower, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 8, duration: 1800, color: :red
        damage 14000, type: :fire
      end
    end

    phase :two, health_between: {50, 75} do
      inherit_phase :one
      phase_emote "Feel the heat of creation!"
      enrage_modifier 1.3

      ability :summon_constructs, cooldown: 30_000 do
        spawn :add, creature_id: 50632, count: 2, spread: true
      end

      ability :forge_fire, cooldown: 20_000 do
        telegraph :circle, radius: 15, duration: 2500, color: :red
        damage 18000, type: :fire
      end

      ability :tempered_steel, cooldown: 35_000 do
        buff :tempered, duration: 12000
        buff :damage_reduction, duration: 12000
      end

      ability :molten_rain, cooldown: 25_000 do
        telegraph :room_wide, duration: 3000
        damage 10000, type: :fire
        spawn :add, creature_id: 50633, count: 3, spread: true
      end

      ability :searing_brand, cooldown: 22_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :red
        damage 16000, type: :fire
        debuff :branded, duration: 12000, stacks: 2
      end
    end

    phase :three, health_between: {25, 50} do
      inherit_phase :two
      phase_emote "THE FORGE CONSUMES ALL!"
      enrage_modifier 1.5

      ability :volcanic_eruption, cooldown: 28_000 do
        telegraph :room_wide, duration: 4000
        damage 16000, type: :fire
        debuff :erupted, duration: 12000, stacks: 1
      end

      ability :lava_pool, cooldown: 22_000, target: :random do
        telegraph :circle, radius: 12, duration: 2500, color: :red
        damage 20000, type: :fire
      end

      ability :mass_constructs, cooldown: 35_000 do
        spawn :add, creature_id: 50632, count: 4, spread: true
      end

      ability :furnace_blast, cooldown: 25_000 do
        telegraph :cone, angle: 120, length: 30, duration: 3000, color: :red
        damage 22000, type: :fire
      end

      ability :inferno_wave, cooldown: 30_000 do
        telegraph :line, width: 12, length: 40, duration: 2500, color: :red
        damage 18000, type: :fire
        movement :knockback, distance: 12
      end
    end

    phase :four, health_below: 25 do
      inherit_phase :three
      phase_emote "MY MASTERPIECE... DESTRUCTION!"
      enrage_modifier 1.8

      ability :apocalypse_forge, cooldown: 30_000 do
        telegraph :room_wide, duration: 5000
        damage 22000, type: :fire
        debuff :apocalypse, duration: 20000, stacks: 2
      end

      ability :final_forging, cooldown: 35_000 do
        telegraph :circle, radius: 25, duration: 4000, color: :red
        damage 25000, type: :fire
        movement :knockback, distance: 15, source: :center
      end

      ability :molten_core, cooldown: 40_000, target: :random do
        telegraph :circle, radius: 8, duration: 4000, color: :red
        coordination :stack, min_players: 5, damage: 70000
      end

      ability :forge_mastery, cooldown: 45_000 do
        buff :forge_master, duration: 20000
        buff :damage_increase, duration: 20000
        telegraph :room_wide, duration: 2000
        damage 15000, type: :fire
      end

      ability :ultimate_creation, cooldown: 50_000 do
        spawn :add, creature_id: 50632, count: 3, spread: true
        telegraph :circle, radius: 20, duration: 3000, color: :red
        damage 20000, type: :fire
      end
    end

    on_death do
      loot_table 50603
      achievement 5060  # Veteran Kel Voreth completion
    end
  end
end
