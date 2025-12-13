defmodule BezgelorWorld.Encounter.Bosses.SanctuaryOfTheSwordmaiden.OnduLifeweaver do
  @moduledoc """
  Ondu Lifeweaver encounter - Sanctuary of the Swordmaiden (Second Boss)

  A nature priest who heals and summons guardians. Features:
  - Life Drain channel that heals the boss
  - Guardian adds that must be killed or they heal Ondu
  - Mass Regeneration interruptible heal
  - Nature's Wrath root mechanic

  ## Strategy
  Phase 1 (100-40%): Interrupt Life Drain, kill guardians before they heal boss
  Phase 2 (<40%): Priority interrupt Mass Regeneration, burn through adds

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Ondu Lifeweaver" do
    boss_id 50302
    health 1_700_000
    level 35
    enrage_timer 480_000
    interrupt_armor 2

    phase :one, health_above: 40 do
      phase_emote "Nature protects its children!"

      ability :life_drain, cooldown: 10_000, target: :random, interruptible: true do
        telegraph :line, width: 4, length: 20, duration: 3000, color: :green
        damage 3000, type: :magic
        buff :life_steal, duration: 3000
      end

      ability :summon_guardian, cooldown: 25_000 do
        spawn :add, creature_id: 50312, count: 1
      end

      ability :natures_touch, cooldown: 12_000, target: :tank do
        telegraph :cone, angle: 60, length: 12, duration: 1500, color: :green
        damage 5000, type: :magic
      end

      ability :vine_lash, cooldown: 8_000, target: :random do
        telegraph :line, width: 3, length: 25, duration: 1200, color: :green
        damage 4000, type: :physical
        debuff :bleeding, duration: 6000, stacks: 1
      end

      ability :rejuvenation, cooldown: 20_000 do
        buff :regenerating, duration: 8000
      end
    end

    phase :two, health_below: 40 do
      inherit_phase :one
      phase_emote "The forest demands tribute!"
      enrage_modifier 1.2

      ability :mass_regeneration, cooldown: 35_000, interruptible: true do
        buff :mass_regen, duration: 10000
        telegraph :circle, radius: 15, duration: 4000, color: :green
      end

      ability :natures_wrath, cooldown: 20_000 do
        telegraph :circle, radius: 12, duration: 2500, color: :green
        damage 7000, type: :magic
        debuff :rooted, duration: 3000
      end

      ability :empowered_guardian, cooldown: 30_000 do
        spawn :add, creature_id: 50313, count: 2, spread: true
      end

      ability :overgrowth, cooldown: 25_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :green
        damage 5000, type: :magic
        spawn :add, creature_id: 50318, count: 3, spread: true
      end

      ability :entangling_roots, cooldown: 15_000, target: :healer do
        telegraph :circle, radius: 6, duration: 1800, color: :green
        debuff :rooted, duration: 4000
        damage 4000, type: :physical
      end
    end

    on_death do
      loot_table 50302
    end
  end
end
