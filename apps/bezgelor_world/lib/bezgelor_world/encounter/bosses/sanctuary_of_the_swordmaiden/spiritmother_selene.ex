defmodule BezgelorWorld.Encounter.Bosses.SanctuaryOfTheSwordmaiden.SpiritmotherSelene do
  @moduledoc """
  Spiritmother Selene encounter - Sanctuary of the Swordmaiden (Fourth Boss)

  A spirit guardian who phases between realms. Features:
  - Spirit Lance targeted damage
  - Ethereal Chains requiring coordination to break
  - Phase Shift making boss immune briefly
  - Spirit Storm room-wide damage

  ## Strategy
  Phase 1 (100-60%): Stack for Ethereal Chain breaks, dodge Spirit Lance
  Phase 2 (<60%): Wait out Phase Shift immunity, cooldowns for Spirit Storm

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Spiritmother Selene" do
    boss_id 50304
    health 1_900_000
    level 35
    enrage_timer 480_000
    interrupt_armor 2

    phase :one, health_above: 60 do
      phase_emote "The spirits guide my blade..."

      ability :spirit_lance, cooldown: 8_000, target: :random do
        telegraph :line, width: 3, length: 25, duration: 1500, color: :blue
        damage 5000, type: :magic
      end

      ability :ethereal_chains, cooldown: 20_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :blue
        debuff :chained, duration: 5000
        coordination :stack, min_players: 2, damage: 10000
      end

      ability :spirit_slash, cooldown: 6_000, target: :tank do
        telegraph :cone, angle: 60, length: 12, duration: 1200, color: :blue
        damage 6000, type: :magic
      end

      ability :spectral_grasp, cooldown: 15_000, target: :farthest do
        telegraph :line, width: 4, length: 30, duration: 1500, color: :blue
        movement :pull, distance: 20
        damage 4000, type: :magic
      end

      ability :ghostly_wail, cooldown: 12_000 do
        telegraph :circle, radius: 10, duration: 1800, color: :blue
        damage 4500, type: :magic
        debuff :fear, duration: 2000
      end
    end

    phase :two, health_below: 60 do
      inherit_phase :one
      phase_emote "You cannot harm what you cannot touch!"
      enrage_modifier 1.3

      ability :phase_shift, cooldown: 30_000 do
        buff :ethereal, duration: 8000
        telegraph :circle, radius: 20, duration: 8000, color: :blue
      end

      ability :spirit_storm, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 6000, type: :magic
        debuff :spirit_touched, duration: 10000, stacks: 1
      end

      ability :summon_spirits, cooldown: 35_000 do
        spawn :add, creature_id: 50315, count: 3, spread: true
      end

      ability :soul_rend, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 5, duration: 1500, color: :blue
        damage 7000, type: :magic
        debuff :soul_torn, duration: 8000, stacks: 1
      end

      ability :ethereal_barrage, cooldown: 22_000 do
        telegraph :line, width: 5, length: 35, duration: 2000, color: :blue
        damage 8000, type: :magic
        movement :knockback, distance: 10
      end

      ability :spirit_possession, cooldown: 40_000, target: :random do
        telegraph :circle, radius: 4, duration: 2500, color: :purple
        debuff :possessed, duration: 6000
        coordination :spread, min_distance: 10, damage: 15000
      end
    end

    on_death do
      loot_table 50304
    end
  end
end
