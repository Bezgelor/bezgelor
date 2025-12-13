defmodule BezgelorWorld.Encounter.Bosses.KelVoreth.ForgemasterTrogun do
  @moduledoc """
  Forgemaster Trogun encounter - Kel Voreth (Final Boss)

  The master of the Osun forge who commands fire and metal. Features:
  - Heavy tank buster hammer slam
  - Fire-based cone attacks with burning DOT
  - Construct adds that must be tanked/killed
  - Superheated enrage phase with room-wide fire

  ## Strategy
  Phase 1 (100-60%): Tank positions for cleave, dodge molten spray
  Phase 2 (60-30%): Kill constructs quickly, manage fire debuffs
  Phase 3 (<30%): Heal through superheated damage, burn boss

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Forgemaster Trogun" do
    boss_id 50103
    health 2_000_000
    level 25
    enrage_timer 480_000
    interrupt_armor 3

    # Phase 1: 100% - 60% health
    phase :one, health_above: 60 do
      phase_emote "You dare enter MY forge?!"

      ability :hammer_slam, cooldown: 10_000, target: :tank do
        telegraph :circle, radius: 6, duration: 2000, color: :red
        damage 12000, type: :physical
        debuff :armor_crush, duration: 8000, stacks: 1
      end

      ability :molten_spray, cooldown: 15_000 do
        telegraph :cone, angle: 90, length: 18, duration: 2000, color: :red
        damage 8000, type: :fire
        debuff :burning, duration: 6000, stacks: 2
      end

      ability :forge_strike, cooldown: 8_000, target: :tank do
        damage 7000, type: :physical
      end

      ability :heat_wave, cooldown: 20_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :red
        damage 5000, type: :fire
      end
    end

    # Phase 2: 60% - 30% health - Construct Phase
    phase :two, health_between: {30, 60} do
      inherit_phase :one
      phase_emote "My creations will crush you!"

      ability :summon_construct, cooldown: 25_000 do
        spawn :add, creature_id: 50113, count: 2, spread: true
      end

      ability :molten_metal, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 9000, type: :fire
        debuff :molten, duration: 10000, stacks: 1
      end

      ability :forge_breath, cooldown: 22_000 do
        telegraph :cone, angle: 60, length: 25, duration: 2500, color: :red
        damage 10000, type: :fire
        movement :knockback, distance: 10
      end
    end

    # Phase 3: Below 30% health - Superheated
    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "FEEL THE HEAT OF THE FORGE!"
      enrage_modifier 1.4

      ability :superheated, cooldown: 30_000 do
        buff :superheated, duration: 30000
        telegraph :room_wide, duration: 3000
        damage 6000, type: :fire
      end

      ability :eruption, cooldown: 12_000 do
        telegraph :circle, radius: 10, duration: 1800, color: :red
        damage 10000, type: :fire
        spawn :add, creature_id: 50114, count: 3, spread: true
      end

      ability :inferno_slam, cooldown: 15_000, target: :tank do
        telegraph :circle, radius: 8, duration: 1500, color: :red
        damage 18000, type: :fire
        movement :knockback, distance: 15
      end

      ability :meltdown, cooldown: 45_000 do
        telegraph :room_wide, duration: 5000
        damage 8000, type: :fire
        debuff :melting, duration: 15000, stacks: 3
      end
    end

    on_death do
      loot_table 50103
      achievement 6801  # Kel Voreth completion
    end
  end
end
