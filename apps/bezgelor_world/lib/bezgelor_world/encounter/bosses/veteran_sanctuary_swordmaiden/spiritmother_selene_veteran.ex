defmodule BezgelorWorld.Encounter.Bosses.VeteranSanctuarySwordmaiden.SpiritmotherSeleneVeteran do
  @moduledoc """
  Spiritmother Selene (Veteran) - Veteran Sanctuary of the Swordmaiden (Fourth Boss)

  Enhanced spirit encounter with phase mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Spiritmother Selene (Veteran)" do
    boss_id 50804
    health 4_800_000
    level 50
    enrage_timer 600_000
    interrupt_armor 5

    phase :one, health_above: 65 do
      phase_emote "The spirits cry for vengeance!"

      ability :spirit_bolt, cooldown: 8_000, target: :tank do
        damage 24000, type: :magic
        debuff :spirit_touched, duration: 10000, stacks: 1
      end

      ability :spirit_storm, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :blue
        damage 16000, type: :magic
      end

      ability :summon_spirits, cooldown: 25_000 do
        spawn :add, creature_id: 50842, count: 3, spread: true
      end

      ability :wail_of_the_dead, cooldown: 18_000 do
        telegraph :cone, angle: 90, length: 30, duration: 2500, color: :blue
        damage 18000, type: :magic
        debuff :terrified, duration: 4000
      end
    end

    phase :two, health_between: {35, 65} do
      inherit_phase :one
      phase_emote "Rise, my children!"
      enrage_modifier 1.35

      ability :spirit_wave, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 16000, type: :magic
        spawn :add, creature_id: 50842, count: 4, spread: true
      end

      ability :ethereal_chains, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 6, duration: 3000, color: :blue
        coordination :spread, min_distance: 10, damage: 20000
      end

      ability :spirit_form, cooldown: 35_000 do
        buff :ethereal, duration: 10000
        buff :damage_reduction, duration: 10000
      end
    end

    phase :three, health_below: 35 do
      inherit_phase :two
      phase_emote "VENGEANCE INCARNATE!"
      enrage_modifier 1.6

      ability :spirit_apocalypse, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 22000, type: :magic
        debuff :doomed, duration: 20000, stacks: 2
      end

      ability :mass_possession, cooldown: 40_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 50842, count_per_wave: 4
      end

      ability :final_wail, cooldown: 45_000 do
        telegraph :circle, radius: 25, duration: 4000, color: :blue
        damage 25000, type: :magic
        coordination :stack, min_players: 5, damage: 60000
      end
    end

    on_death do
      loot_table 50804
    end
  end
end
