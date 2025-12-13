defmodule BezgelorWorld.Encounter.Bosses.UltimateProtogames.RoboTank do
  @moduledoc """
  Robo-Tank encounter - Ultimate Protogames (Second Boss)

  A massive war machine designed for the Protogames arena. Features:
  - Fire damage focused attacks
  - Missile Barrage random targeting
  - Deploys turret adds that must be destroyed
  - Overdrive enrage in final phase

  ## Strategy
  Phase 1 (100-60%): Avoid Flamethrower cone, dodge Missile Barrage
  Phase 2 (60-30%): Destroy turrets quickly, survive Carpet Bomb
  Phase 3 (<30%): Burn before Nuclear Option wipes the raid

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Robo-Tank" do
    boss_id 50402
    health 2_400_000
    level 50
    enrage_timer 480_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "INITIATING COMBAT PROTOCOLS. TARGET ACQUIRED."

      ability :tank_cannon, cooldown: 10_000, target: :tank do
        damage 14000, type: :fire
        debuff :heated_armor, duration: 10000, stacks: 1
      end

      ability :missile_barrage, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 9000, type: :fire
      end

      ability :flamethrower, cooldown: 18_000 do
        telegraph :cone, angle: 60, length: 25, duration: 2500, color: :red
        damage 11000, type: :fire
        debuff :burning, duration: 6000, stacks: 1
      end

      ability :tread_marks, cooldown: 20_000 do
        telegraph :line, width: 8, length: 35, duration: 2000, color: :brown
        damage 10000, type: :physical
        movement :knockback, distance: 8
      end

      ability :targeting_laser, cooldown: 12_000, target: :random do
        telegraph :line, width: 3, length: 30, duration: 1500, color: :red
        damage 8000, type: :fire
      end
    end

    phase :two, health_between: {30, 60} do
      inherit_phase :one
      phase_emote "DEPLOYING SECONDARY WEAPONS SYSTEMS."
      enrage_modifier 1.25

      ability :deploy_turrets, cooldown: 35_000 do
        spawn :add, creature_id: 50422, count: 2, spread: true
      end

      ability :carpet_bomb, cooldown: 30_000 do
        telegraph :room_wide, duration: 4000
        damage 10000, type: :fire
        debuff :scorched, duration: 8000, stacks: 1
      end

      ability :lock_on, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 5, duration: 1500, color: :red
        damage 13000, type: :fire
      end

      ability :minefield, cooldown: 25_000 do
        spawn :add, creature_id: 50423, count: 5, spread: true
        telegraph :room_wide, duration: 1000
      end

      ability :smoke_screen, cooldown: 40_000 do
        buff :obscured, duration: 8000
        telegraph :room_wide, duration: 2000
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "CRITICAL DAMAGE DETECTED. ENGAGING OVERDRIVE."
      enrage_modifier 1.5

      ability :overdrive, cooldown: 45_000 do
        buff :overdrive, duration: 15000
        buff :damage_increase, duration: 15000
      end

      ability :nuclear_option, cooldown: 35_000 do
        telegraph :circle, radius: 20, duration: 4000, color: :red
        damage 15000, type: :fire
        movement :knockback, distance: 15, source: :center
      end

      ability :rapid_fire, cooldown: 8_000 do
        telegraph :cone, angle: 45, length: 30, duration: 1500, color: :red
        damage 8000, type: :fire
      end

      ability :self_destruct_warning, cooldown: 60_000 do
        telegraph :room_wide, duration: 6000
        damage 18000, type: :fire
      end
    end

    on_death do
      loot_table 50402
    end
  end
end
