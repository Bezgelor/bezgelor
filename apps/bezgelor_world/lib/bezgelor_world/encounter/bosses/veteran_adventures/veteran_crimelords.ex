defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranCrimelords do
  @moduledoc """
  Veteran Crimelords adventure bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Kingpin Kraz (Veteran)" do
    boss_id 71401
    health 5_200_000
    level 50
    enrage_timer 360_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "You think you can take down THE Kingpin?!"

      ability :brass_knuckles, cooldown: 5_000, target: :tank do
        damage 28000, type: :physical
        debuff :dazed, duration: 3000
      end

      ability :money_shot, cooldown: 10_000, target: :random do
        telegraph :line, width: 5, length: 30, duration: 1500, color: :yellow
        damage 24000, type: :physical
        coordination :spread, damage: 42000, min_distance: 6
      end

      ability :intimidate, cooldown: 15_000 do
        telegraph :cone, angle: 120, length: 22, duration: 2000, color: :red
        damage 22000, type: :physical
        debuff :terrified, duration: 4000
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "GET 'EM, BOYS!"
      enrage_modifier 1.4

      ability :call_enforcers, cooldown: 22_000 do
        spawn :add, creature_id: 71411, count: 5, spread: true
      end

      ability :explosive_briefcase, cooldown: 18_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :red
        damage 38000, type: :fire
      end

      ability :executive_fury, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 42000, type: :physical
      end
    end

    on_death do
      loot_table 71401
    end
  end

  boss "The Collector (Veteran)" do
    boss_id 71402
    health 5_800_000
    level 50
    enrage_timer 420_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "Your soul will be my finest acquisition..."

      ability :soul_drain, cooldown: 5_000, target: :tank do
        damage 30000, type: :shadow
        buff :soul_power, duration: 10000
      end

      ability :collection_cage, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 7, duration: 2000, color: :purple
        damage 22000, type: :shadow
        debuff :imprisoned, duration: 5000
      end

      ability :dark_tendrils, cooldown: 10_000 do
        telegraph :cross, length: 25, width: 4, duration: 1800, color: :purple
        damage 26000, type: :shadow
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "BEHOLD MY MAGNIFICENT COLLECTION!"
      enrage_modifier 1.45

      ability :unleash_collection, cooldown: 22_000 do
        spawn :add, creature_id: 71421, count: 6, spread: true
      end

      ability :soul_storm, cooldown: 20_000 do
        telegraph :room_wide, duration: 4000
        damage 38000, type: :shadow
      end

      ability :collection_complete, cooldown: 25_000 do
        telegraph :donut, inner_radius: 4, outer_radius: 14, duration: 2500, color: :purple
        damage 35000, type: :shadow
      end
    end

    on_death do
      loot_table 71402
    end
  end

  boss "Crime Lord Supreme (Veteran)" do
    boss_id 71403
    health 7_500_000
    level 50
    enrage_timer 540_000
    interrupt_armor 4

    phase :one, health_above: 65 do
      phase_emote "I own this city. I AM the law!"

      ability :executive_order, cooldown: 5_000, target: :tank do
        damage 35000, type: :physical
      end

      ability :hostile_takeover, cooldown: 10_000, target: :random do
        telegraph :circle, radius: 9, duration: 1800, color: :red
        damage 28000, type: :physical
        coordination :spread, damage: 50000, min_distance: 8
      end

      ability :power_play, cooldown: 12_000 do
        telegraph :cone, angle: 120, length: 26, duration: 2000, color: :red
        damage 32000, type: :physical
      end
    end

    phase :two, health_between: [35, 65] do
      inherit_phase :one
      phase_emote "ELIMINATE THEM! EVERY LAST ONE!"
      enrage_modifier 1.45

      ability :call_assassins, cooldown: 22_000 do
        spawn :add, creature_id: 71431, count: 4, spread: true
      end

      ability :criminal_empire, cooldown: 28_000 do
        buff :empire_power, duration: 18000
        buff :damage_increase, duration: 18000
      end

      ability :contract_hit, cooldown: 18_000, target: :healer do
        damage 40000, type: :physical
        debuff :marked_for_death, duration: 8000
      end
    end

    phase :three, health_below: 35 do
      inherit_phase :two
      phase_emote "YOU'LL NEVER TAKE ME ALIVE!"
      enrage_modifier 1.8

      ability :final_order, cooldown: 22_000 do
        telegraph :room_wide, duration: 4500
        damage 52000, type: :physical
      end

      ability :desperation, cooldown: 15_000 do
        telegraph :cross, length: 30, width: 6, duration: 2000, color: :red
        damage 45000, type: :physical
      end
    end

    on_death do
      loot_table 71403
      achievement 7140  # Veteran Crimelords completion
    end
  end
end
