defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.Zoetic do
  @moduledoc """
  Zoetic - World Boss in Wilderrun.
  Ancient primal entity requiring 20+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Zoetic" do
    boss_id 80003
    health 65_000_000
    level 35
    enrage_timer 900_000
    interrupt_armor 7

    phase :one, health_above: 70 do
      phase_emote "YOU DISTURB THE ANCIENT BALANCE!"

      ability :primal_strike, cooldown: 5_000, target: :tank do
        damage 52000, type: :nature
        debuff :nature_vulnerability, duration: 12000, stacks: 1
      end

      ability :life_drain, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :green
        damage 40000, type: :nature
        buff :regeneration, duration: 10000
      end

      ability :root_eruption, cooldown: 15_000 do
        telegraph :cross, length: 35, width: 8, duration: 2500, color: :green
        damage 38000, type: :nature
        debuff :rooted, duration: 5000
      end

      ability :summon_guardians, cooldown: 30_000 do
        spawn :add, creature_id: 80031, count: 6, spread: true
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase :one
      phase_emote "THE WILDS RISE AGAINST YOU!"
      enrage_modifier 1.35

      ability :nature_fury, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 50000, type: :nature
      end

      ability :mass_entangle, cooldown: 25_000 do
        telegraph :circle, radius: 25, duration: 3000, color: :green
        damage 35000, type: :nature
        debuff :rooted, duration: 6000
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "NATURE RECLAIMS ALL!"
      enrage_modifier 1.6

      ability :apocalyptic_growth, cooldown: 40_000 do
        telegraph :room_wide, duration: 6000
        damage 70000, type: :nature
      end

      ability :primal_avatar, cooldown: 35_000 do
        buff :primal_form, duration: 20000
        buff :damage_increase, duration: 20000
        spawn :add, creature_id: 80032, count: 8, spread: true
      end
    end

    on_death do
      loot_table 80003
      achievement 8003  # Zoetic Slayer
    end
  end
end
