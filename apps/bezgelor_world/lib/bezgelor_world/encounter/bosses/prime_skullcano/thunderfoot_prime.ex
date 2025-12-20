defmodule BezgelorWorld.Encounter.Bosses.PrimeSkullcano.ThunderfootPrime do
  @moduledoc """
  Thunderfoot (Prime) - Second boss of Prime Skullcano.
  Massive beast with devastating stomp and charge attacks.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Thunderfoot (Prime)" do
    boss_id(13102)
    health(12_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("*THUNDEROUS ROAR*")

      ability :crushing_stomp, cooldown: 5_000, target: :tank do
        damage(40000, type: :physical)
        debuff(:armor_break, duration: 10000, stacks: 1)
      end

      ability :thunder_stomp, cooldown: 10_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :brown)
        damage(32000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :charge, cooldown: 18_000, target: :farthest do
        telegraph(:line, width: 6, length: 35, duration: 1800, color: :red)
        damage(35000, type: :physical)
        debuff(:stunned, duration: 2000)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("*ENRAGED BELLOWING*")
      enrage_modifier(1.4)

      ability :earthquake, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3000)
        damage(38000, type: :physical)
        movement(:knockback, distance: 5)
      end

      ability :rampage, cooldown: 25_000 do
        buff(:rampaging, duration: 15000)
        buff(:speed_increase, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("*PRIMAL FURY*")
      enrage_modifier(1.8)

      ability :cataclysmic_stomp, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(55000, type: :physical)
      end

      ability :stampede, cooldown: 20_000 do
        telegraph(:line, width: 8, length: 40, duration: 2000, color: :red)
        damage(48000, type: :physical)
        spawn(:add, creature_id: 13121, count: 4, spread: true)
      end
    end

    on_death do
      loot_table(13102)
    end
  end
end
