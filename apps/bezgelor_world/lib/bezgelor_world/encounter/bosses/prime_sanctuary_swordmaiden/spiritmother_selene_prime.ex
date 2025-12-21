defmodule BezgelorWorld.Encounter.Bosses.PrimeSanctuarySwordmaiden.SpiritmotherSelenePrime do
  @moduledoc """
  Spiritmother Selene (Prime) - Fourth boss of Prime SSM.
  Spirit priestess with divine and shadow magic.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Spiritmother Selene (Prime)" do
    boss_id(14104)
    health(12_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(5)

    phase :one, health_above: 60 do
      phase_emote("The spirits guide my hand!")

      ability :spirit_lance, cooldown: 5_000, target: :tank do
        damage(38000, type: :magic)
        debuff(:spirit_weakness, duration: 10000, stacks: 1)
      end

      ability :spirit_bomb, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :white)
        damage(30000, type: :magic)
        coordination(:spread, damage: 50000, min_distance: 8)
      end

      ability :spirit_wave, cooldown: 15_000 do
        telegraph(:cone, angle: 75, length: 26, duration: 2000, color: :white)
        damage(35000, type: :magic)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("SPIRITS OF THE SANCTUARY, AID ME!")
      enrage_modifier(1.4)

      ability :summon_spirits, cooldown: 25_000 do
        spawn(:add, creature_id: 14141, count: 4, spread: true)
      end

      ability :spiritual_infusion, cooldown: 30_000 do
        buff(:spirit_shield, duration: 15000)
        buff(:damage_reduction, duration: 15000)
      end

      ability :spirit_storm, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3500)
        damage(42000, type: :magic)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("THE SPIRITS DEMAND SACRIFICE!")
      enrage_modifier(1.7)

      ability :apocalyptic_ritual, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4500)
        damage(58000, type: :magic)
      end

      ability :spirit_cross, cooldown: 18_000 do
        telegraph(:cross, length: 32, width: 6, duration: 2000, color: :white)
        damage(48000, type: :magic)
      end

      ability :death_mark, cooldown: 25_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :red)
        coordination(:stack, damage: 80000, required_players: 3)
      end
    end

    on_death do
      loot_table(14104)
    end
  end
end
