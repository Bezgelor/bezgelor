defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.Kraggar do
  @moduledoc """
  Kraggar - World Boss in Malgrave.
  Massive desert beast requiring 20+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Kraggar" do
    boss_id(80005)
    health(80_000_000)
    level(45)
    enrage_timer(900_000)
    interrupt_armor(8)

    phase :one, health_above: 70 do
      phase_emote("*EARTH-SHAKING ROAR*")

      ability :crushing_bite, cooldown: 5_000, target: :tank do
        damage(62000, type: :physical)
        debuff(:bleeding, duration: 12000, stacks: 3)
      end

      ability :sand_blast, cooldown: 10_000, target: :random do
        telegraph(:cone, angle: 90, length: 35, duration: 2000, color: :brown)
        damage(48000, type: :physical)
        debuff(:blinded, duration: 5000)
      end

      ability :burrow_charge, cooldown: 18_000, target: :farthest do
        telegraph(:line, width: 10, length: 50, duration: 2500, color: :brown)
        damage(55000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :summon_brood, cooldown: 30_000 do
        spawn(:add, creature_id: 80051, count: 8, spread: true)
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase(:one)
      phase_emote("*FURIOUS ROAR*")
      enrage_modifier(1.35)

      ability :earthquake, cooldown: 35_000 do
        telegraph(:room_wide, duration: 5000)
        damage(60000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :sand_storm, cooldown: 28_000 do
        telegraph(:circle, radius: 30, duration: 3000, color: :brown)
        damage(50000, type: :physical)
        debuff(:slowed, duration: 8000)
      end
    end

    phase :three, health_below: 40 do
      inherit_phase(:two)
      phase_emote("*PRIMAL RAGE*")
      enrage_modifier(1.6)

      ability :cataclysm, cooldown: 40_000 do
        telegraph(:room_wide, duration: 6000)
        damage(80000, type: :physical)
      end

      ability :desert_fury, cooldown: 30_000 do
        buff(:desert_avatar, duration: 20000)
        buff(:damage_increase, duration: 20000)
        spawn(:add, creature_id: 80052, count: 10, spread: true)
      end
    end

    on_death do
      loot_table(80005)
      # Kraggar Slayer
      achievement(8005)
    end
  end
end
