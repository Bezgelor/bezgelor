defmodule BezgelorWorld.Encounter.Bosses.VeteranSanctuarySwordmaiden.OnduLifeweaverVeteran do
  @moduledoc """
  Ondu Lifeweaver (Veteran) - Veteran Sanctuary of the Swordmaiden (Second Boss)

  Enhanced nature healing encounter with interrupt mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Ondu Lifeweaver (Veteran)" do
    boss_id(50802)
    health(4_000_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("Nature's wrath shall cleanse you!")

      ability :vine_strike, cooldown: 8_000, target: :tank do
        damage(20000, type: :nature)
        debuff(:entangled, duration: 4000)
      end

      ability :wild_growth, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :green)
        damage(14000, type: :nature)
      end

      ability :natures_blessing, cooldown: 20_000, interruptible: true do
        buff(:regenerating, duration: 10000)
      end

      ability :thorn_volley, cooldown: 12_000 do
        telegraph(:cone, angle: 60, length: 25, duration: 2000, color: :green)
        damage(16000, type: :nature)
      end
    end

    phase :two, health_below: 60 do
      inherit_phase(:one)
      phase_emote("The forest rises against you!")
      enrage_modifier(1.35)

      ability :overgrowth, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(14000, type: :nature)
        debuff(:overgrown, duration: 12000, stacks: 1)
      end

      ability :spawn_treants, cooldown: 30_000 do
        spawn(:add, creature_id: 50822, count: 3, spread: true)
      end

      ability :life_drain, cooldown: 22_000, target: :random do
        telegraph(:line, width: 6, length: 35, duration: 2500, color: :green)
        damage(16000, type: :nature)
        buff(:life_stolen, duration: 8000)
      end

      ability :natures_wrath, cooldown: 35_000 do
        telegraph(:circle, radius: 20, duration: 3500, color: :green)
        damage(20000, type: :nature)
      end
    end

    on_death do
      loot_table(50802)
    end
  end
end
