defmodule BezgelorWorld.Encounter.Bosses.Expeditions.CrimelordsOfWhitevale do
  @moduledoc """
  Crimelords of Whitevale expedition bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Redmoon Enforcer" do
    boss_id(51201)
    health(700_000)
    level(30)
    enrage_timer(240_000)
    interrupt_armor(2)

    phase :one, health_above: 40 do
      phase_emote("Time to collect!")

      ability :pistol_shot, cooldown: 6_000, target: :tank do
        damage(6000, type: :physical)
      end

      ability :grenade_toss, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :red)
        damage(5000, type: :fire)
      end

      ability :spray_and_pray, cooldown: 15_000 do
        telegraph(:cone, angle: 60, length: 20, duration: 2000, color: :red)
        damage(5500, type: :physical)
      end
    end

    phase :two, health_below: 40 do
      inherit_phase(:one)
      phase_emote("Backup incoming!")
      enrage_modifier(1.3)

      ability :call_reinforcements, cooldown: 25_000 do
        spawn(:add, creature_id: 51211, count: 3, spread: true)
      end

      ability :explosive_finale, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3000)
        damage(7000, type: :fire)
      end
    end

    on_death do
      loot_table(51201)
    end
  end

  boss "Crime Boss Gorax" do
    boss_id(51202)
    health(1_100_000)
    level(30)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("Nobody messes with Gorax!")

      ability :boss_slam, cooldown: 8_000, target: :tank do
        damage(8000, type: :physical)
      end

      ability :money_toss, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1500, color: :yellow)
        damage(5000, type: :physical)
      end

      ability :dirty_tricks, cooldown: 18_000 do
        telegraph(:cone, angle: 90, length: 22, duration: 2000, color: :red)
        damage(7000, type: :physical)
        debuff(:blinded, duration: 3000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("GUARDS! GET THEM!")
      enrage_modifier(1.35)

      ability :call_the_boys, cooldown: 25_000 do
        spawn(:add, creature_id: 51221, count: 4, spread: true)
      end

      ability :executive_order, cooldown: 28_000 do
        telegraph(:room_wide, duration: 3500)
        damage(9000, type: :physical)
      end

      ability :desperation_strike, cooldown: 20_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :red)
        damage(10000, type: :physical)
      end
    end

    on_death do
      loot_table(51202)
      # Crimelords completion
      achievement(5120)
    end
  end
end
