defmodule BezgelorWorld.Encounter.Bosses.KelVoreth.SlavemasterDrokk do
  @moduledoc """
  Slavemaster Drokk encounter - Kel Voreth (Second Boss)

  A brutal Osun slavemaster who uses chains and whips. Features:
  - Chain pull mechanic requiring positioning
  - Bleeding DOT from lash attacks
  - Prisoner adds that aid players if freed
  - Whip frenzy AoE in enrage phase

  ## Strategy
  Phase 1 (100-50%): Stay at mid-range to avoid chain pull, free prisoners
  Phase 2 (<50%): Stack for whip frenzy healing, burn boss quickly

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Slavemaster Drokk" do
    boss_id(50102)
    health(1_650_000)
    level(25)
    enrage_timer(360_000)
    interrupt_armor(2)

    # Phase 1: 100% - 50% health
    phase :one, health_above: 50 do
      phase_emote("Another batch of slaves for the forge!")

      ability :lash, cooldown: 5_000, target: :tank do
        damage(5000, type: :physical)
        debuff(:bleeding, duration: 8000, stacks: 1)
      end

      ability :chain_pull, cooldown: 12_000, target: :farthest do
        telegraph(:line, width: 3, length: 30, duration: 1500, color: :purple)
        movement(:pull, distance: 25)
        damage(4000, type: :physical)
        debuff(:chained, duration: 3000)
      end

      ability :crack_the_whip, cooldown: 15_000, target: :random do
        telegraph(:line, width: 4, length: 20, duration: 1800, color: :red)
        damage(6000, type: :physical)
      end

      ability :intimidate, cooldown: 20_000 do
        telegraph(:cone, angle: 90, length: 15, duration: 2000, color: :purple)
        damage(3000, type: :physical)
        debuff(:fear, duration: 3000)
      end
    end

    # Phase 2: Below 50% health - Frenzy Phase
    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("You will learn to OBEY!")
      enrage_modifier(1.2)

      ability :whip_frenzy, cooldown: 8_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :red)
        damage(7000, type: :physical)
      end

      ability :chains_of_binding, cooldown: 25_000, target: :healer do
        telegraph(:circle, radius: 6, duration: 2500, color: :purple)
        debuff(:bound, duration: 5000)
        damage(4000, type: :physical)
        coordination(:stack, min_players: 2, damage: 20000)
      end

      ability :slave_driver, cooldown: 30_000 do
        spawn(:add, creature_id: 50112, count: 2, spread: true, aggro: :healer)
        buff(:empowered, duration: 10000)
      end

      ability :execute, cooldown: 18_000, target: :lowest_health do
        telegraph(:circle, radius: 5, duration: 1500, color: :red)
        damage(12000, type: :physical)
      end
    end

    on_death do
      loot_table(50102)
    end
  end
end
