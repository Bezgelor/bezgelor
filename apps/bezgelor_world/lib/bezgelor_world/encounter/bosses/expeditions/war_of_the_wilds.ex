defmodule BezgelorWorld.Encounter.Bosses.Expeditions.WarOfTheWilds do
  @moduledoc """
  War of the Wilds expedition bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Jungle Beast" do
    boss_id(51101)
    health(900_000)
    level(40)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 40 do
      phase_emote("RAAAAWR!")

      ability :savage_bite, cooldown: 8_000, target: :tank do
        damage(10000, type: :physical)
        debuff(:bleeding, duration: 8000, stacks: 1)
      end

      ability :pounce, cooldown: 15_000, target: :farthest do
        telegraph(:line, width: 4, length: 30, duration: 1800, color: :red)
        damage(8000, type: :physical)
      end

      ability :roar, cooldown: 20_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :red)
        damage(6000, type: :physical)
        debuff(:terrified, duration: 3000)
      end
    end

    phase :two, health_below: 40 do
      inherit_phase(:one)
      phase_emote("THE HUNT BEGINS!")
      enrage_modifier(1.35)

      ability :frenzy, cooldown: 30_000 do
        buff(:frenzied, duration: 10000)
        buff(:damage_increase, duration: 10000)
      end

      ability :summon_pack, cooldown: 25_000 do
        spawn(:add, creature_id: 51111, count: 3, spread: true)
      end
    end

    on_death do
      loot_table(51101)
    end
  end

  boss "Alpha Predator" do
    boss_id(51102)
    health(1_400_000)
    level(40)
    enrage_timer(360_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("I am the apex!")

      ability :alpha_strike, cooldown: 8_000, target: :tank do
        damage(12000, type: :physical)
      end

      ability :territorial_roar, cooldown: 15_000 do
        telegraph(:cone, angle: 90, length: 25, duration: 2000, color: :red)
        damage(9000, type: :physical)
      end

      ability :ground_slam, cooldown: 12_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :brown)
        damage(8000, type: :physical)
        movement(:knockback, distance: 8)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("NONE ESCAPE THE ALPHA!")
      enrage_modifier(1.4)

      ability :primal_fury, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(10000, type: :physical)
      end

      ability :call_of_the_wild, cooldown: 30_000 do
        spawn(:add, creature_id: 51121, count: 4, spread: true)
      end

      ability :rending_claws, cooldown: 18_000 do
        telegraph(:cross, length: 25, width: 5, duration: 2000, color: :red)
        damage(11000, type: :physical)
      end
    end

    on_death do
      loot_table(51102)
      # War of the Wilds completion
      achievement(5110)
    end
  end
end
