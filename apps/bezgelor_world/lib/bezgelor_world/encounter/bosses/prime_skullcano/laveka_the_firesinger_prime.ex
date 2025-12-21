defmodule BezgelorWorld.Encounter.Bosses.PrimeSkullcano.LavekaTheFiresingerPrime do
  @moduledoc """
  Laveka the Firesinger (Prime) - Final boss of Prime Skullcano.
  Volcanic shaman with devastating fire and lava mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Laveka the Firesinger (Prime)" do
    boss_id(13103)
    health(17_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(5)

    phase :one, health_above: 70 do
      phase_emote("The volcano awakens at my call!")

      ability :fire_bolt, cooldown: 5_000, target: :tank do
        damage(42000, type: :fire)
        debuff(:burning, duration: 10000, stacks: 2)
      end

      ability :lava_burst, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :orange)
        damage(35000, type: :fire)
        coordination(:spread, damage: 55000, min_distance: 8)
      end

      ability :fire_wave, cooldown: 15_000 do
        telegraph(:cone, angle: 75, length: 28, duration: 2000, color: :orange)
        damage(38000, type: :fire)
      end
    end

    phase :two, health_between: [45, 70] do
      inherit_phase(:one)
      phase_emote("FEEL THE VOLCANO'S WRATH!")
      enrage_modifier(1.35)

      ability :summon_fire_elementals, cooldown: 30_000 do
        spawn(:add, creature_id: 13131, count: 3, spread: true)
      end

      ability :volcanic_eruption, cooldown: 22_000 do
        telegraph(:circle, radius: 12, duration: 2500, color: :orange)
        damage(45000, type: :fire)
        debuff(:burning, duration: 10000, stacks: 2)
      end

      ability :meteor_strike, cooldown: 18_000, target: :random do
        telegraph(:circle, radius: 6, duration: 2000, color: :red)
        damage(40000, type: :fire)
      end
    end

    phase :three, health_between: [20, 45] do
      inherit_phase(:two)
      phase_emote("THE MOUNTAIN BLEEDS FIRE!")
      enrage_modifier(1.6)

      ability :pyroclastic_flow, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(60000, type: :fire)
      end

      ability :fire_cross, cooldown: 18_000 do
        telegraph(:cross, length: 35, width: 6, duration: 2000, color: :orange)
        damage(50000, type: :fire)
      end

      ability :magma_prison, cooldown: 22_000, target: :healer do
        telegraph(:circle, radius: 6, duration: 2000, color: :red)
        coordination(:stack, damage: 80000, required_players: 3)
        debuff(:imprisoned, duration: 4000)
      end
    end

    phase :four, health_below: 20 do
      inherit_phase(:three)
      phase_emote("BECOME ONE WITH THE INFERNO!")
      enrage_modifier(2.0)

      ability :volcanic_apocalypse, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(80000, type: :fire)
      end

      ability :avatar_of_flame, cooldown: 25_000 do
        buff(:flame_avatar, duration: 20000)
        buff(:damage_increase, duration: 20000)
        buff(:fire_aura, duration: 20000)
      end
    end

    on_death do
      loot_table(13103)
      # Prime Skullcano completion
      achievement(1310)
    end
  end
end
