defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranWarWilds do
  @moduledoc """
  Veteran War of the Wilds adventure bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Jungle Warlord (Veteran)" do
    boss_id(71501)
    health(6_000_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("The jungle is OURS!")

      ability :primal_strike, cooldown: 5_000, target: :tank do
        damage(32000, type: :physical)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end

      ability :spear_throw, cooldown: 10_000, target: :farthest do
        telegraph(:line, width: 4, length: 35, duration: 1500, color: :brown)
        damage(28000, type: :physical)
      end

      ability :war_drums, cooldown: 18_000 do
        buff(:war_frenzy, duration: 15000)
        spawn(:add, creature_id: 71511, count: 3, spread: true)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("WARRIORS! BLOOD FOR THE JUNGLE!")
      enrage_modifier(1.45)

      ability :tribal_summon, cooldown: 22_000 do
        spawn(:add, creature_id: 71512, count: 5, spread: true)
      end

      ability :berserker_rage, cooldown: 25_000 do
        telegraph(:circle, radius: 15, duration: 2000, color: :red)
        damage(38000, type: :physical)
        buff(:enraged, duration: 12000)
      end

      ability :warlord_fury, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(42000, type: :physical)
      end
    end

    on_death do
      loot_table(71501)
    end
  end

  boss "Primal Guardian (Veteran)" do
    boss_id(71502)
    health(7_000_000)
    level(50)
    enrage_timer(480_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("THE JUNGLE SPIRITS RISE!")

      ability :nature_strike, cooldown: 5_000, target: :tank do
        damage(35000, type: :nature)
      end

      ability :entangling_vines, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :green)
        damage(25000, type: :nature)
        debuff(:rooted, duration: 5000)
        coordination(:spread, damage: 45000, min_distance: 6)
      end

      ability :spirit_blast, cooldown: 12_000 do
        telegraph(:cone, angle: 75, length: 28, duration: 2000, color: :green)
        damage(30000, type: :nature)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("THE SPIRITS DEMAND SACRIFICE!")
      enrage_modifier(1.45)

      ability :summon_spirits, cooldown: 22_000 do
        spawn(:add, creature_id: 71521, count: 4, spread: true)
      end

      ability :nature_wrath, cooldown: 20_000 do
        telegraph(:room_wide, duration: 4000)
        damage(42000, type: :nature)
      end

      ability :primal_cross, cooldown: 15_000 do
        telegraph(:cross, length: 28, width: 5, duration: 2000, color: :green)
        damage(35000, type: :nature)
      end
    end

    on_death do
      loot_table(71502)
    end
  end

  boss "Nature's Vengeance (Veteran)" do
    boss_id(71503)
    health(9_000_000)
    level(50)
    enrage_timer(600_000)
    interrupt_armor(4)

    phase :one, health_above: 65 do
      phase_emote("YOU HAVE DESECRATED THE SACRED GROVE!")

      ability :vengeful_strike, cooldown: 5_000, target: :tank do
        damage(40000, type: :nature)
        debuff(:nature_vulnerability, duration: 12000, stacks: 2)
      end

      ability :thorn_storm, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 10, duration: 1800, color: :green)
        damage(32000, type: :nature)
        coordination(:spread, damage: 55000, min_distance: 8)
      end

      ability :primal_wave, cooldown: 12_000 do
        telegraph(:cone, angle: 120, length: 30, duration: 2000, color: :green)
        damage(35000, type: :nature)
      end
    end

    phase :two, health_between: [35, 65] do
      inherit_phase(:one)
      phase_emote("THE JUNGLE HUNGERS FOR YOUR FLESH!")
      enrage_modifier(1.45)

      ability :spawn_treants, cooldown: 22_000 do
        spawn(:add, creature_id: 71531, count: 5, spread: true)
      end

      ability :overgrowth, cooldown: 18_000 do
        telegraph(:donut, inner_radius: 6, outer_radius: 18, duration: 2500, color: :green)
        damage(45000, type: :nature)
      end

      ability :nature_prison, cooldown: 25_000, target: :healer do
        debuff(:imprisoned, duration: 6000)
        damage(25000, type: :nature)
      end
    end

    phase :three, health_below: 35 do
      inherit_phase(:two)
      phase_emote("ALL WILL RETURN TO THE EARTH!")
      enrage_modifier(1.8)

      ability :apocalyptic_growth, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4500)
        damage(58000, type: :nature)
      end

      ability :final_vengeance, cooldown: 18_000 do
        telegraph(:cross, length: 35, width: 7, duration: 2000, color: :green)
        damage(50000, type: :nature)
      end
    end

    on_death do
      loot_table(71503)
      # Veteran War of the Wilds completion
      achievement(7150)
    end
  end
end
