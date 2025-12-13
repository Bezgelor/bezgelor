defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.DreadwatcherTyrix do
  @moduledoc """
  Dreadwatcher Tyrix - World Boss in Grimvault.
  Ultimate world boss requiring 40+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Dreadwatcher Tyrix" do
    boss_id 80006
    health 100_000_000
    level 50
    enrage_timer 1200_000
    interrupt_armor 10

    phase :one, health_above: 75 do
      phase_emote "YOU HAVE AWAKENED THE DREADWATCHER. PREPARE FOR ANNIHILATION."

      ability :dread_strike, cooldown: 5_000, target: :tank do
        damage 75000, type: :shadow
        debuff :dread, duration: 15000, stacks: 1
      end

      ability :void_blast, cooldown: 10_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :purple
        damage 55000, type: :shadow
        coordination :spread, damage: 90000, min_distance: 12
      end

      ability :terror_wave, cooldown: 15_000 do
        telegraph :cone, angle: 120, length: 40, duration: 2500, color: :purple
        damage 50000, type: :shadow
        debuff :terrified, duration: 5000
      end

      ability :summon_horrors, cooldown: 30_000 do
        spawn :add, creature_id: 80061, count: 8, spread: true
      end
    end

    phase :two, health_between: [50, 75] do
      inherit_phase :one
      phase_emote "THE DREAD CONSUMES ALL!"
      enrage_modifier 1.3

      ability :nightmare_zone, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 65000, type: :shadow
        debuff :dread, duration: 20000, stacks: 2
      end

      ability :void_cross, cooldown: 22_000 do
        telegraph :cross, length: 50, width: 12, duration: 2500, color: :purple
        damage 60000, type: :shadow
      end
    end

    phase :three, health_between: [25, 50] do
      inherit_phase :two
      phase_emote "EMBRACE OBLIVION!"
      enrage_modifier 1.5

      ability :mass_terror, cooldown: 40_000 do
        telegraph :room_wide, duration: 6000
        damage 80000, type: :shadow
      end

      ability :dread_lords, cooldown: 35_000 do
        spawn :add, creature_id: 80062, count: 4, spread: true
      end

      ability :void_prison, cooldown: 25_000, target: :healer do
        debuff :imprisoned, duration: 8000
        damage 40000, type: :shadow
        coordination :stack, damage: 100000, required_players: 5
      end
    end

    phase :four, health_below: 25 do
      inherit_phase :three
      phase_emote "ALL EXISTENCE SHALL END IN DREAD!"
      enrage_modifier 1.8

      ability :apocalyptic_dread, cooldown: 45_000 do
        telegraph :room_wide, duration: 7000
        damage 100000, type: :shadow
      end

      ability :avatar_of_dread, cooldown: 40_000 do
        buff :dread_avatar, duration: 25000
        buff :damage_increase, duration: 25000
        spawn :add, creature_id: 80063, count: 12, spread: true
      end

      ability :final_oblivion, cooldown: 30_000 do
        telegraph :donut, inner_radius: 10, outer_radius: 30, duration: 3000, color: :purple
        damage 85000, type: :shadow
      end
    end

    on_death do
      loot_table 80006
      achievement 8006  # Dreadwatcher Slayer
    end
  end
end
