defmodule BezgelorWorld.Encounter.Bosses.PrimeKelVoreth.ForgemasterTrogunPrime do
  @moduledoc """
  Forgemaster Trogun (Prime) - Final boss of Prime Kel Voreth.
  Master blacksmith with devastating fire and forge mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Forgemaster Trogun (Prime)" do
    boss_id(12103)
    health(16_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(5)

    phase :one, health_above: 70 do
      phase_emote("You dare desecrate the sacred forge?!")

      ability :hammer_of_the_forge, cooldown: 5_000, target: :tank do
        damage(42000, type: :physical)
        debuff(:heat_exhaustion, duration: 10000, stacks: 1)
      end

      ability :molten_slag, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :orange)
        damage(32000, type: :fire)
        debuff(:burning, duration: 8000, stacks: 2)
        coordination(:spread, damage: 50000, min_distance: 8)
      end

      ability :forge_breath, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 25, duration: 2000, color: :orange)
        damage(35000, type: :fire)
      end
    end

    phase :two, health_between: [45, 70] do
      inherit_phase(:one)
      phase_emote("THE FORGE HEATS TO CRITICAL!")
      enrage_modifier(1.35)

      ability :summon_constructs, cooldown: 30_000 do
        spawn(:add, creature_id: 12131, count: 3, spread: true)
      end

      ability :lava_eruption, cooldown: 20_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :orange)
        damage(40000, type: :fire)
        debuff(:burning, duration: 8000, stacks: 1)
      end

      ability :superheated_chains, cooldown: 18_000, target: :healer do
        debuff(:chained, duration: 5000)
        damage(25000, type: :fire)
      end
    end

    phase :three, health_between: [20, 45] do
      inherit_phase(:two)
      phase_emote("I AM THE FORGE INCARNATE!")
      enrage_modifier(1.6)

      ability :forge_nova, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :fire)
      end

      ability :molten_cross, cooldown: 18_000 do
        telegraph(:cross, length: 32, width: 6, duration: 2000, color: :orange)
        damage(45000, type: :fire)
      end

      ability :iron_maiden, cooldown: 22_000, target: :random do
        telegraph(:circle, radius: 6, duration: 2000, color: :red)
        coordination(:stack, damage: 70000, required_players: 3)
      end
    end

    phase :four, health_below: 20 do
      inherit_phase(:three)
      phase_emote("THE FORGE WILL CONSUME ALL!")
      enrage_modifier(2.0)

      ability :apocalyptic_eruption, cooldown: 30_000 do
        telegraph(:room_wide, duration: 5000)
        damage(75000, type: :fire)
      end

      ability :molten_avatar, cooldown: 25_000 do
        buff(:molten_avatar, duration: 20000)
        buff(:damage_increase, duration: 20000)
        buff(:fire_aura, duration: 20000)
      end
    end

    on_death do
      loot_table(12103)
      # Prime Kel Voreth completion
      achievement(1210)
    end
  end
end
