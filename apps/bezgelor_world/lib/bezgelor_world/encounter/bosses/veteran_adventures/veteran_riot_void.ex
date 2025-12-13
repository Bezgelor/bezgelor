defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranRiotVoid do
  @moduledoc """
  Veteran Riot in the Void adventure bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Void Warden (Veteran)" do
    boss_id 71601
    health 5_500_000
    level 50
    enrage_timer 420_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "THE VOID PROTECTS ITS SECRETS!"

      ability :void_strike, cooldown: 5_000, target: :tank do
        damage 30000, type: :shadow
        debuff :void_touched, duration: 10000, stacks: 2
      end

      ability :shadow_bolt, cooldown: 8_000, target: :random do
        telegraph :line, width: 4, length: 30, duration: 1500, color: :purple
        damage 25000, type: :shadow
      end

      ability :void_zone, cooldown: 12_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :purple
        damage 22000, type: :shadow
        debuff :slowed, duration: 5000
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "THE VOID CONSUMES ALL!"
      enrage_modifier 1.45

      ability :summon_void_spawn, cooldown: 22_000 do
        spawn :add, creature_id: 71611, count: 4, spread: true
      end

      ability :void_nova, cooldown: 20_000 do
        telegraph :room_wide, duration: 4000
        damage 38000, type: :shadow
      end

      ability :dark_cross, cooldown: 15_000 do
        telegraph :cross, length: 28, width: 5, duration: 2000, color: :purple
        damage 32000, type: :shadow
      end
    end

    on_death do
      loot_table 71601
    end
  end

  boss "Chaos Harbinger (Veteran)" do
    boss_id 71602
    health 6_500_000
    level 50
    enrage_timer 480_000
    interrupt_armor 3

    phase :one, health_above: 50 do
      phase_emote "CHAOS IS THE ONLY TRUTH!"

      ability :chaos_strike, cooldown: 5_000, target: :tank do
        damage 35000, type: :magic
      end

      ability :reality_tear, cooldown: 10_000, target: :random do
        telegraph :circle, radius: 9, duration: 1800, color: :purple
        damage 28000, type: :magic
        coordination :spread, damage: 50000, min_distance: 8
      end

      ability :chaos_wave, cooldown: 12_000 do
        telegraph :cone, angle: 90, length: 28, duration: 2000, color: :purple
        damage 32000, type: :magic
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "EMBRACE THE CHAOS!"
      enrage_modifier 1.45

      ability :summon_chaos, cooldown: 22_000 do
        spawn :add, creature_id: 71621, count: 5, spread: true
      end

      ability :entropy_field, cooldown: 18_000 do
        telegraph :donut, inner_radius: 5, outer_radius: 15, duration: 2500, color: :purple
        damage 40000, type: :magic
      end

      ability :reality_collapse, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 45000, type: :magic
      end
    end

    on_death do
      loot_table 71602
    end
  end

  boss "Entropy Lord (Veteran)" do
    boss_id 71603
    health 8_500_000
    level 50
    enrage_timer 600_000
    interrupt_armor 4

    phase :one, health_above: 65 do
      phase_emote "ALL ORDER MUST END IN ENTROPY!"

      ability :entropy_strike, cooldown: 5_000, target: :tank do
        damage 40000, type: :shadow
        debuff :entropy, duration: 12000, stacks: 2
      end

      ability :void_eruption, cooldown: 10_000, target: :random do
        telegraph :circle, radius: 10, duration: 1800, color: :purple
        damage 32000, type: :shadow
        coordination :spread, damage: 55000, min_distance: 8
      end

      ability :chaos_beam, cooldown: 12_000 do
        telegraph :line, width: 6, length: 35, duration: 2000, color: :purple
        damage 35000, type: :shadow
      end
    end

    phase :two, health_between: [35, 65] do
      inherit_phase :one
      phase_emote "REALITY CRUMBLES BEFORE ME!"
      enrage_modifier 1.45

      ability :summon_entropy, cooldown: 22_000 do
        spawn :add, creature_id: 71631, count: 5, spread: true
      end

      ability :void_prison, cooldown: 18_000, target: :healer do
        debuff :imprisoned, duration: 6000
        damage 25000, type: :shadow
      end

      ability :entropic_cross, cooldown: 15_000 do
        telegraph :cross, length: 32, width: 6, duration: 2000, color: :purple
        damage 42000, type: :shadow
      end
    end

    phase :three, health_below: 35 do
      inherit_phase :two
      phase_emote "ALL SHALL RETURN TO NOTHING!"
      enrage_modifier 1.8

      ability :apocalyptic_entropy, cooldown: 25_000 do
        telegraph :room_wide, duration: 4500
        damage 58000, type: :shadow
      end

      ability :final_chaos, cooldown: 18_000 do
        telegraph :donut, inner_radius: 7, outer_radius: 20, duration: 2500, color: :purple
        damage 50000, type: :shadow
      end

      ability :lord_of_entropy, cooldown: 30_000 do
        buff :entropy_avatar, duration: 18000
        buff :damage_increase, duration: 18000
      end
    end

    on_death do
      loot_table 71603
      achievement 7160  # Veteran Riot in the Void completion
    end
  end
end
