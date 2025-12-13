defmodule BezgelorWorld.Encounter.Bosses.Adventures.RiotInTheVoidAdventure do
  @moduledoc """
  Riot in the Void Adventure bosses.
  Navigate through void-touched territory.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Void Warden" do
    boss_id 70601
    health 2_400_000
    level 35
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "The void protects its secrets!"

      ability :void_strike, cooldown: 5_000, target: :tank do
        damage 12000, type: :shadow
        debuff :void_touched, duration: 8000, stacks: 1
      end

      ability :shadow_bolt, cooldown: 10_000, target: :random do
        telegraph :line, width: 3, length: 25, duration: 1500, color: :purple
        damage 10000, type: :shadow
      end

      ability :void_zone, cooldown: 15_000 do
        telegraph :circle, radius: 8, duration: 2000, color: :purple
        damage 9000, type: :shadow
        debuff :slowed, duration: 4000
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "THE VOID CONSUMES!"
      enrage_modifier 1.35

      ability :summon_void_spawn, cooldown: 25_000 do
        spawn :add, creature_id: 70611, count: 3, spread: true
      end

      ability :void_nova, cooldown: 22_000 do
        telegraph :room_wide, duration: 3500
        damage 15000, type: :shadow
      end
    end

    on_death do
      loot_table 70601
    end
  end

  boss "Chaos Harbinger" do
    boss_id 70602
    health 2_800_000
    level 35
    enrage_timer 330_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "Chaos is the only truth!"

      ability :chaos_strike, cooldown: 5_000, target: :tank do
        damage 14000, type: :magic
      end

      ability :reality_tear, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 7, duration: 1800, color: :purple
        damage 11000, type: :magic
        coordination :spread, damage: 20000, min_distance: 6
      end

      ability :chaos_wave, cooldown: 15_000 do
        telegraph :cone, angle: 75, length: 22, duration: 2000, color: :purple
        damage 13000, type: :magic
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "EMBRACE THE CHAOS!"
      enrage_modifier 1.4

      ability :summon_chaos, cooldown: 25_000 do
        spawn :add, creature_id: 70621, count: 4, spread: true
      end

      ability :entropy_field, cooldown: 22_000 do
        telegraph :donut, inner_radius: 4, outer_radius: 12, duration: 2500, color: :purple
        damage 16000, type: :magic
      end
    end

    on_death do
      loot_table 70602
    end
  end

  boss "Entropy Lord" do
    boss_id 70603
    health 3_500_000
    level 35
    enrage_timer 420_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "All order must end in entropy!"

      ability :entropy_strike, cooldown: 5_000, target: :tank do
        damage 16000, type: :shadow
        debuff :entropy, duration: 10000, stacks: 1
      end

      ability :void_eruption, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 8, duration: 1800, color: :purple
        damage 13000, type: :shadow
        coordination :spread, damage: 24000, min_distance: 8
      end

      ability :chaos_beam, cooldown: 15_000 do
        telegraph :line, width: 5, length: 30, duration: 2000, color: :purple
        damage 15000, type: :shadow
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "REALITY CRUMBLES!"
      enrage_modifier 1.45

      ability :summon_entropy, cooldown: 25_000 do
        spawn :add, creature_id: 70631, count: 4, spread: true
      end

      ability :void_prison, cooldown: 22_000, target: :healer do
        debuff :imprisoned, duration: 5000
        damage 10000, type: :shadow
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "ALL SHALL RETURN TO NOTHING!"
      enrage_modifier 1.8

      ability :apocalyptic_entropy, cooldown: 28_000 do
        telegraph :room_wide, duration: 4000
        damage 25000, type: :shadow
      end

      ability :final_chaos, cooldown: 20_000 do
        telegraph :cross, length: 28, width: 6, duration: 2000, color: :purple
        damage 22000, type: :shadow
      end
    end

    on_death do
      loot_table 70603
      achievement 7060  # Riot in the Void Adventure completion
    end
  end
end
