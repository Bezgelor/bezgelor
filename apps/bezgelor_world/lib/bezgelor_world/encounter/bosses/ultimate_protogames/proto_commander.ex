defmodule BezgelorWorld.Encounter.Bosses.UltimateProtogames.ProtoCommander do
  @moduledoc """
  Proto-Commander encounter - Ultimate Protogames (Third Boss)

  A military commander overseeing the Protogames arena. Features:
  - Rallies troops throughout the fight
  - Tactical Laser precision attacks
  - Artillery Strike room-wide damage
  - Mass deployment of adds in final phase

  ## Strategy
  Phase 1 (100-65%): Kill rallied troops quickly, avoid Tactical Laser
  Phase 2 (65-35%): Burn shield, survive Artillery Strike
  Phase 3 (<35%): Handle mass deployment, interrupt when possible

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Proto-Commander" do
    boss_id 50403
    health 2_600_000
    level 50
    enrage_timer 540_000
    interrupt_armor 3

    phase :one, health_above: 65 do
      phase_emote "Attention contestants! The Commander is here!"

      ability :command_strike, cooldown: 10_000, target: :tank do
        damage 13000, type: :physical
        debuff :commanded, duration: 8000, stacks: 1
      end

      ability :rally_troops, cooldown: 25_000 do
        spawn :add, creature_id: 50432, count: 3, spread: true
      end

      ability :tactical_laser, cooldown: 15_000 do
        telegraph :line, width: 4, length: 35, duration: 2000, color: :red
        damage 10000, type: :magic
      end

      ability :grenade_volley, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 8, duration: 1800, color: :red
        damage 8000, type: :fire
      end

      ability :march_orders, cooldown: 18_000 do
        buff :ordered, duration: 6000
        telegraph :circle, radius: 10, duration: 1500, color: :blue
      end
    end

    phase :two, health_between: {35, 65} do
      inherit_phase :one
      phase_emote "Time to escalate! BRING IN THE HEAVY ARTILLERY!"
      enrage_modifier 1.3

      ability :artillery_strike, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 10000, type: :fire
        debuff :shell_shocked, duration: 8000, stacks: 1
      end

      ability :deploy_shield, cooldown: 35_000 do
        buff :shielded, duration: 8000
        buff :damage_reduction, duration: 8000
      end

      ability :suppression_fire, cooldown: 18_000 do
        telegraph :cone, angle: 90, length: 30, duration: 2500, color: :red
        damage 11000, type: :physical
      end

      ability :smoke_bomb, cooldown: 25_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :gray
        debuff :blinded, duration: 4000
      end

      ability :reinforcements, cooldown: 40_000 do
        spawn :add, creature_id: 50432, count: 2, spread: true
        spawn :add, creature_id: 50433, count: 1, spread: true
      end
    end

    phase :three, health_below: 35 do
      inherit_phase :two
      phase_emote "FINAL PROTOCOL ENGAGED! ALL UNITS ATTACK!"
      enrage_modifier 1.5

      ability :mass_deployment, cooldown: 35_000 do
        spawn :wave, waves: 2, delay: 5000, creature_id: 50432, count_per_wave: 4
      end

      ability :orbital_strike, cooldown: 25_000 do
        telegraph :circle, radius: 15, duration: 3000, color: :red
        damage 14000, type: :fire
      end

      ability :last_stand, cooldown: 60_000 do
        buff :last_stand, duration: 20000
        buff :damage_increase, duration: 20000
      end

      ability :desperation_fire, cooldown: 12_000 do
        telegraph :cross, length: 30, width: 5, duration: 2000, color: :red
        damage 12000, type: :fire
      end

      ability :final_order, cooldown: 45_000 do
        telegraph :room_wide, duration: 3500
        damage 15000, type: :physical
        spawn :add, creature_id: 50432, count: 6, spread: true
      end
    end

    on_death do
      loot_table 50403
    end
  end
end
