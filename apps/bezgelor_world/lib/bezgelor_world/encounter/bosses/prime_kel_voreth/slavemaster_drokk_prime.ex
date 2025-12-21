defmodule BezgelorWorld.Encounter.Bosses.PrimeKelVoreth.SlavemasterDrokkPrime do
  @moduledoc """
  Slavemaster Drokk (Prime) - Second boss of Prime Kel Voreth.
  Brutal taskmaster with overwhelming minion waves.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Slavemaster Drokk (Prime)" do
    boss_id(12102)
    health(11_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("More slaves for the forge! WORK HARDER!")

      ability :brutal_lash, cooldown: 5_000, target: :tank do
        damage(38000, type: :physical)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end

      ability :whip_crack, cooldown: 10_000 do
        telegraph(:line, width: 5, length: 28, duration: 1500, color: :red)
        damage(30000, type: :physical)
      end

      ability :call_slaves, cooldown: 25_000 do
        spawn(:add, creature_id: 12121, count: 4, spread: true)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("ALL SLAVES WILL OBEY OR DIE!")
      enrage_modifier(1.4)

      ability :chain_pull, cooldown: 15_000, target: :farthest do
        movement(:pull, distance: 20)
        damage(25000, type: :physical)
        debuff(:stunned, duration: 2000)
      end

      ability :suppression_wave, cooldown: 20_000 do
        telegraph(:cone, angle: 90, length: 25, duration: 2000, color: :red)
        damage(35000, type: :physical)
        debuff(:slowed, duration: 6000)
      end

      ability :slave_uprising, cooldown: 30_000 do
        spawn(:add, creature_id: 12122, count: 6, spread: true)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("IF I FALL, YOU ALL BURN WITH ME!")
      enrage_modifier(1.7)

      ability :mass_execution, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(48000, type: :physical)
      end

      ability :desperate_strike, cooldown: 18_000 do
        telegraph(:cross, length: 30, width: 5, duration: 2000, color: :red)
        damage(40000, type: :physical)
      end
    end

    on_death do
      loot_table(12102)
    end
  end
end
