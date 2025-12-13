defmodule BezgelorWorld.Encounter.Bosses.VeteranKelVoreth.GrondTheCorpsemakerVeteran do
  @moduledoc """
  Grond the Corpsemaker (Veteran) encounter - Veteran Kel Voreth (First Boss)

  The veteran version of Grond with enhanced undead mechanics. Features:
  - Higher damage and more corpse adds
  - Corpse Explosion room-wide AoE
  - Wave-based corpse spawning in phase 2

  ## Strategy
  Phase 1 (100-60%): Kill corpse adds quickly, avoid Gore cone
  Phase 2 (<60%): Survive Corpse Explosion, handle mass corpse waves

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Grond the Corpsemaker (Veteran)" do
    boss_id 50601
    health 3_800_000
    level 50
    enrage_timer 480_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "Fresh meat for the corpse pile!"

      ability :corpse_cleave, cooldown: 8_000, target: :tank do
        damage 20000, type: :physical
        debuff :cleaved, duration: 10000, stacks: 1
      end

      ability :gore, cooldown: 12_000 do
        telegraph :cone, angle: 90, length: 20, duration: 2000, color: :red
        damage 15000, type: :physical
        debuff :gored, duration: 8000, stacks: 1
      end

      ability :corpse_throw, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :green
        damage 12000, type: :physical
      end

      ability :raise_dead, cooldown: 20_000 do
        spawn :add, creature_id: 50612, count: 2, spread: true
      end

      ability :bone_crush, cooldown: 18_000, target: :tank do
        damage 18000, type: :physical
        movement :knockback, distance: 8
      end
    end

    phase :two, health_below: 60 do
      inherit_phase :one
      phase_emote "MORE BODIES FOR THE PILE!"
      enrage_modifier 1.4

      ability :mass_corpses, cooldown: 30_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 50612, count_per_wave: 3
      end

      ability :corpse_explosion, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 14000, type: :physical
        debuff :decaying, duration: 12000, stacks: 1
      end

      ability :enraged_cleave, cooldown: 18_000 do
        telegraph :cone, angle: 180, length: 25, duration: 2500, color: :red
        damage 18000, type: :physical
      end

      ability :corpse_rain, cooldown: 25_000 do
        telegraph :room_wide, duration: 3000
        damage 10000, type: :physical
        spawn :add, creature_id: 50612, count: 4, spread: true
      end

      ability :death_grip, cooldown: 35_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :green
        damage 12000, type: :physical
        movement :pull, distance: 15
      end
    end

    on_death do
      loot_table 50601
    end
  end
end
