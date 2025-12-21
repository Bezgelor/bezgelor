defmodule BezgelorWorld.Encounter.Bosses.Adventures.BayOfBetrayal do
  @moduledoc """
  Bay of Betrayal adventure bosses.
  Pirate-themed adventure with treachery and treasure.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Captain Mordechai" do
    boss_id(70301)
    health(2_800_000)
    level(40)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("Ye'll never take me treasure!")

      ability :cutlass_slash, cooldown: 5_000, target: :tank do
        damage(14000, type: :physical)
        debuff(:bleeding, duration: 8000, stacks: 1)
      end

      ability :pistol_shot, cooldown: 10_000, target: :random do
        telegraph(:line, width: 2, length: 30, duration: 1200, color: :red)
        damage(12000, type: :physical)
      end

      ability :grog_bomb, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :orange)
        damage(10000, type: :fire)
        debuff(:confused, duration: 3000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("CREW! DEFEND YER CAPTAIN!")
      enrage_modifier(1.35)

      ability :summon_crew, cooldown: 25_000 do
        spawn(:add, creature_id: 70311, count: 4, spread: true)
      end

      ability :cannon_barrage, cooldown: 22_000 do
        telegraph(:circle, radius: 6, duration: 1500, color: :red)
        damage(16000, type: :fire)
      end
    end

    on_death do
      loot_table(70301)
    end
  end

  boss "First Mate Venko" do
    boss_id(70302)
    health(2_500_000)
    level(40)
    enrage_timer(300_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("The Captain trusts me... foolishly.")

      ability :backstab, cooldown: 5_000, target: :tank do
        damage(15000, type: :physical)
      end

      ability :poison_blade, cooldown: 12_000, target: :random do
        telegraph(:line, width: 3, length: 20, duration: 1500, color: :green)
        damage(11000, type: :nature)
        debuff(:poisoned, duration: 10000, stacks: 2)
      end

      ability :smoke_bomb, cooldown: 18_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :gray)
        damage(8000, type: :physical)
        debuff(:blinded, duration: 4000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("Time for the REAL betrayal!")
      enrage_modifier(1.4)

      ability :call_mutineers, cooldown: 25_000 do
        spawn(:add, creature_id: 70321, count: 3, spread: true)
      end

      ability :treacherous_strike, cooldown: 20_000 do
        telegraph(:cross, length: 22, width: 4, duration: 1800, color: :purple)
        damage(18000, type: :physical)
      end
    end

    on_death do
      loot_table(70302)
    end
  end

  boss "The Betrayer" do
    boss_id(70303)
    health(4_000_000)
    level(40)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("All this... was according to plan.")

      ability :shadow_strike, cooldown: 5_000, target: :tank do
        damage(18000, type: :shadow)
        debuff(:shadow_vulnerability, duration: 10000, stacks: 1)
      end

      ability :dark_blast, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 7, duration: 1800, color: :purple)
        damage(14000, type: :shadow)
        coordination(:spread, damage: 25000, min_distance: 6)
      end

      ability :void_wave, cooldown: 15_000 do
        telegraph(:cone, angle: 75, length: 24, duration: 2000, color: :purple)
        damage(16000, type: :shadow)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("You cannot escape your doom!")
      enrage_modifier(1.4)

      ability :summon_shadows, cooldown: 25_000 do
        spawn(:add, creature_id: 70331, count: 4, spread: true)
      end

      ability :betrayal_curse, cooldown: 22_000, target: :healer do
        debuff(:cursed, duration: 8000)
        damage(12000, type: :shadow)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("THIS CANNOT BE! I PLANNED EVERYTHING!")
      enrage_modifier(1.7)

      ability :shadow_apocalypse, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(25000, type: :shadow)
      end

      ability :final_betrayal, cooldown: 20_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 15, duration: 2500, color: :purple)
        damage(22000, type: :shadow)
      end
    end

    on_death do
      loot_table(70303)
      # Bay of Betrayal completion
      achievement(7030)
    end
  end
end
