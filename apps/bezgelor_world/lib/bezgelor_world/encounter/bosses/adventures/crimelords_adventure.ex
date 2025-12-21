defmodule BezgelorWorld.Encounter.Bosses.Adventures.CrimelordsAdventure do
  @moduledoc """
  Crimelords Adventure bosses.
  Take down the criminal underworld of Whitevale.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Kingpin Kraz" do
    boss_id(70401)
    health(2_200_000)
    level(30)
    enrage_timer(270_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("You think you can take on the Kingpin?!")

      ability :brass_knuckles, cooldown: 5_000, target: :tank do
        damage(11000, type: :physical)
        debuff(:dazed, duration: 2000)
      end

      ability :money_shot, cooldown: 12_000, target: :random do
        telegraph(:line, width: 4, length: 25, duration: 1500, color: :yellow)
        damage(9000, type: :physical)
      end

      ability :intimidate, cooldown: 18_000 do
        telegraph(:cone, angle: 90, length: 18, duration: 2000, color: :red)
        damage(8000, type: :physical)
        debuff(:terrified, duration: 3000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("BOYS! SHOW 'EM HOW WE DO BUSINESS!")
      enrage_modifier(1.35)

      ability :call_enforcers, cooldown: 25_000 do
        spawn(:add, creature_id: 70411, count: 4, spread: true)
      end

      ability :explosive_briefcase, cooldown: 22_000 do
        telegraph(:circle, radius: 8, duration: 2000, color: :red)
        damage(15000, type: :fire)
      end
    end

    on_death do
      loot_table(70401)
    end
  end

  boss "The Collector" do
    boss_id(70402)
    health(2_500_000)
    level(30)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("Your soul will make a fine addition to my collection...")

      ability :soul_drain, cooldown: 5_000, target: :tank do
        damage(12000, type: :shadow)
        buff(:soul_power, duration: 8000)
      end

      ability :collection_cage, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :purple)
        damage(8000, type: :shadow)
        debuff(:imprisoned, duration: 4000)
      end

      ability :dark_tendrils, cooldown: 12_000 do
        telegraph(:cross, length: 20, width: 3, duration: 1800, color: :purple)
        damage(10000, type: :shadow)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("BEHOLD MY COLLECTION!")
      enrage_modifier(1.4)

      ability :unleash_collection, cooldown: 25_000 do
        spawn(:add, creature_id: 70421, count: 5, spread: true)
      end

      ability :soul_storm, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3500)
        damage(14000, type: :shadow)
      end
    end

    on_death do
      loot_table(70402)
    end
  end

  boss "Crime Lord Supreme" do
    boss_id(70403)
    health(3_200_000)
    level(30)
    enrage_timer(360_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("I run this town. I AM the law!")

      ability :executive_order, cooldown: 5_000, target: :tank do
        damage(14000, type: :physical)
      end

      ability :hostile_takeover, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :red)
        damage(11000, type: :physical)
        coordination(:spread, damage: 20000, min_distance: 6)
      end

      ability :power_play, cooldown: 15_000 do
        telegraph(:cone, angle: 90, length: 22, duration: 2000, color: :red)
        damage(13000, type: :physical)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("ELIMINATE THEM! ALL OF THEM!")
      enrage_modifier(1.4)

      ability :call_assassins, cooldown: 25_000 do
        spawn(:add, creature_id: 70431, count: 3, spread: true)
      end

      ability :criminal_empire, cooldown: 30_000 do
        buff(:empire_power, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("YOU'LL NEVER TAKE ME ALIVE!")
      enrage_modifier(1.7)

      ability :final_order, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(22000, type: :physical)
      end

      ability :desperation, cooldown: 18_000 do
        telegraph(:cross, length: 25, width: 5, duration: 2000, color: :red)
        damage(18000, type: :physical)
      end
    end

    on_death do
      loot_table(70403)
      # Crimelords Adventure completion
      achievement(7040)
    end
  end
end
