defmodule BezgelorWorld.Encounter.Bosses.KelVoreth.GrondTheCorpsemaker do
  @moduledoc """
  Grond the Corpsemaker encounter - Kel Voreth (First Boss)

  An Osun necromancer who raises the dead to fight for him. Features:
  - Frontal cleave attack requiring tank positioning
  - Skeleton adds that must be killed or they explode
  - Corpse explosion targeting dead adds
  - Bone storm room-wide damage in final phase

  ## Strategy
  Phase 1 (100-70%): Tank faces boss away, DPS kills skeleton adds
  Phase 2 (70-30%): Move away from corpses before explosion, stack for heals
  Phase 3 (<30%): Burn boss, use cooldowns for Bone Storm

  Data sources: instance_bosses.json, texts.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Grond the Corpsemaker" do
    boss_id 50101
    health 1_500_000
    level 25
    enrage_timer 420_000
    interrupt_armor 2

    # Phase 1: 100% - 70% health
    phase :one, health_above: 70 do
      phase_emote "Rise, my minions! Feast upon their flesh!"

      ability :cleave, cooldown: 6_000, target: :tank do
        telegraph :cone, angle: 120, length: 12, duration: 1500, color: :red
        damage 6000, type: :physical
      end

      ability :summon_skeleton, cooldown: 20_000 do
        spawn :add, creature_id: 50111, count: 3, spread: true
      end

      ability :bone_spike, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 4, duration: 1800, color: :red
        damage 5000, type: :physical
        debuff :impaled, duration: 4000, stacks: 1
      end
    end

    # Phase 2: 70% - 30% health - Corpse Phase
    phase :two, health_between: {30, 70} do
      inherit_phase :one
      phase_emote "The dead shall consume you!"

      ability :corpse_explosion, cooldown: 15_000 do
        telegraph :circle, radius: 10, duration: 2500, color: :red
        damage 8000, type: :magic
      end

      ability :death_grip, cooldown: 18_000, target: :healer do
        telegraph :line, width: 3, length: 25, duration: 1500, color: :purple
        movement :pull, distance: 20
        damage 4000, type: :magic
      end

      ability :necrotic_wave, cooldown: 25_000 do
        telegraph :circle, radius: 15, duration: 2000, color: :purple
        damage 5000, type: :magic
        debuff :necrotic, duration: 10000, stacks: 2
      end
    end

    # Phase 3: Below 30% health - Bone Storm
    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "BONE STORM! You will join my army!"
      enrage_modifier 1.3

      ability :bone_storm, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 5000, type: :physical
        movement :knockback, distance: 8, source: :center
      end

      ability :mass_resurrection, cooldown: 40_000 do
        spawn :wave, waves: 2, delay: 3000, creature_id: 50111, count_per_wave: 4
        buff :frenzy, duration: 15000
      end
    end

    on_death do
      loot_table 50101
    end
  end
end
