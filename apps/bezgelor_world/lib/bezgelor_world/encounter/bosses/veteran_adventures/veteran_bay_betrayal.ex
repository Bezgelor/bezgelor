defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranBayBetrayal do
  @moduledoc """
  Veteran Bay of Betrayal adventure bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Captain Mordechai (Veteran)" do
    boss_id(71301)
    health(6_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("YE'LL NEVER TAKE ME TREASURE, SCALLYWAGS!")

      ability :cutlass_slash, cooldown: 5_000, target: :tank do
        damage(32000, type: :physical)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end

      ability :pistol_shot, cooldown: 8_000, target: :random do
        telegraph(:line, width: 3, length: 35, duration: 1200, color: :red)
        damage(28000, type: :physical)
      end

      ability :grog_bomb, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 9, duration: 1800, color: :orange)
        damage(25000, type: :fire)
        debuff(:confused, duration: 4000)
        coordination(:spread, damage: 45000, min_distance: 6)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("CREW! SEND THESE DOGS TO DAVY JONES!")
      enrage_modifier(1.4)

      ability :summon_crew, cooldown: 22_000 do
        spawn(:add, creature_id: 71311, count: 5, spread: true)
      end

      ability :cannon_barrage, cooldown: 18_000 do
        telegraph(:circle, radius: 8, duration: 1500, color: :red)
        damage(38000, type: :fire)
      end

      ability :broadside, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(42000, type: :fire)
      end
    end

    on_death do
      loot_table(71301)
    end
  end

  boss "First Mate Venko (Veteran)" do
    boss_id(71302)
    health(5_500_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("Trust is for the foolish...")

      ability :backstab, cooldown: 5_000, target: :tank do
        damage(35000, type: :physical)
      end

      ability :poison_blade, cooldown: 10_000, target: :random do
        telegraph(:line, width: 4, length: 25, duration: 1500, color: :green)
        damage(28000, type: :nature)
        debuff(:poisoned, duration: 12000, stacks: 3)
      end

      ability :smoke_bomb, cooldown: 15_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :gray)
        damage(22000, type: :physical)
        debuff(:blinded, duration: 5000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("THE REAL BETRAYAL BEGINS!")
      enrage_modifier(1.45)

      ability :call_mutineers, cooldown: 22_000 do
        spawn(:add, creature_id: 71321, count: 4, spread: true)
      end

      ability :treacherous_strike, cooldown: 18_000 do
        telegraph(:cross, length: 28, width: 5, duration: 1800, color: :purple)
        damage(40000, type: :physical)
      end

      ability :assassinate, cooldown: 25_000, target: :healer do
        damage(45000, type: :physical)
        debuff(:marked_for_death, duration: 8000)
      end
    end

    on_death do
      loot_table(71302)
    end
  end

  boss "The Betrayer (Veteran)" do
    boss_id(71303)
    health(9_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(4)

    phase :one, health_above: 65 do
      phase_emote("Everything... goes according to MY plan.")

      ability :shadow_strike, cooldown: 5_000, target: :tank do
        damage(38000, type: :shadow)
        debuff(:shadow_vulnerability, duration: 12000, stacks: 2)
      end

      ability :dark_blast, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 9, duration: 1800, color: :purple)
        damage(32000, type: :shadow)
        coordination(:spread, damage: 55000, min_distance: 8)
      end

      ability :void_wave, cooldown: 12_000 do
        telegraph(:cone, angle: 90, length: 28, duration: 2000, color: :purple)
        damage(35000, type: :shadow)
      end
    end

    phase :two, health_between: [35, 65] do
      inherit_phase(:one)
      phase_emote("YOU CANNOT ESCAPE YOUR DOOM!")
      enrage_modifier(1.4)

      ability :summon_shadows, cooldown: 22_000 do
        spawn(:add, creature_id: 71331, count: 5, spread: true)
      end

      ability :betrayal_curse, cooldown: 18_000, target: :healer do
        debuff(:cursed, duration: 10000)
        damage(28000, type: :shadow)
      end

      ability :dark_cross, cooldown: 15_000 do
        telegraph(:cross, length: 30, width: 6, duration: 2000, color: :purple)
        damage(38000, type: :shadow)
      end
    end

    phase :three, health_below: 35 do
      inherit_phase(:two)
      phase_emote("THIS CANNOT BE! I PLANNED EVERYTHING!")
      enrage_modifier(1.8)

      ability :shadow_apocalypse, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4500)
        damage(55000, type: :shadow)
      end

      ability :final_betrayal, cooldown: 18_000 do
        telegraph(:donut, inner_radius: 6, outer_radius: 18, duration: 2500, color: :purple)
        damage(48000, type: :shadow)
      end

      ability :absolute_darkness, cooldown: 30_000 do
        buff(:darkness_avatar, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    on_death do
      loot_table(71303)
      # Veteran Bay of Betrayal completion
      achievement(7130)
    end
  end
end
