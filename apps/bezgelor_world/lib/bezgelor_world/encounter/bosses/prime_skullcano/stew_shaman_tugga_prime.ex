defmodule BezgelorWorld.Encounter.Bosses.PrimeSkullcano.StewShamanTuggaPrime do
  @moduledoc """
  Stew-Shaman Tugga (Prime) - First boss of Prime Skullcano.
  Marauder shaman with toxic stew and poison mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stew-Shaman Tugga (Prime)" do
    boss_id(13101)
    health(9_500_000)
    level(50)
    enrage_timer(360_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("Tugga's stew gonna melt ya bones!")

      ability :toxic_splash, cooldown: 5_000, target: :tank do
        damage(32000, type: :nature)
        debuff(:poisoned, duration: 10000, stacks: 2)
      end

      ability :stew_bomb, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :green)
        damage(28000, type: :nature)
        coordination(:spread, damage: 45000, min_distance: 6)
      end

      ability :noxious_cloud, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 22, duration: 2000, color: :green)
        damage(30000, type: :nature)
        debuff(:slowed, duration: 5000)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("ADD MORE BONES TO DA STEW!")
      enrage_modifier(1.4)

      ability :summon_cauldron_guards, cooldown: 25_000 do
        spawn(:add, creature_id: 13111, count: 3, spread: true)
      end

      ability :toxic_eruption, cooldown: 20_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :green)
        damage(35000, type: :nature)
        debuff(:poisoned, duration: 8000, stacks: 2)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("TUGGA'S SPECIAL RECIPE!")
      enrage_modifier(1.7)

      ability :toxic_apocalypse, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(52000, type: :nature)
        debuff(:poisoned, duration: 12000, stacks: 3)
      end

      ability :acid_geyser, cooldown: 18_000 do
        telegraph(:cross, length: 28, width: 5, duration: 2000, color: :green)
        damage(42000, type: :nature)
      end
    end

    on_death do
      loot_table(13101)
    end
  end
end
