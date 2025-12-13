defmodule BezgelorWorld.Encounter.Bosses.Adventures.SiegeOfTempestRefuge do
  @moduledoc """
  The Siege of Tempest Refuge adventure bosses.
  Defend the settlement from invading forces.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Skullcrusher" do
    boss_id 70201
    health 2_000_000
    level 25
    enrage_timer 240_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "CRUSH THE DEFENDERS!"

      ability :skull_bash, cooldown: 6_000, target: :tank do
        damage 10000, type: :physical
        debuff :dazed, duration: 3000
      end

      ability :ground_slam, cooldown: 12_000 do
        telegraph :circle, radius: 10, duration: 2000, color: :brown
        damage 8000, type: :physical
        movement :knockback, distance: 6
      end

      ability :war_cry, cooldown: 20_000 do
        buff :war_fury, duration: 10000
        spawn :add, creature_id: 70211, count: 2, spread: true
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "YOU CANNOT STOP THE SIEGE!"
      enrage_modifier 1.3

      ability :rampage, cooldown: 25_000 do
        telegraph :line, width: 6, length: 25, duration: 2000, color: :red
        damage 14000, type: :physical
      end

      ability :siege_call, cooldown: 30_000 do
        spawn :add, creature_id: 70212, count: 4, spread: true
      end
    end

    on_death do
      loot_table 70201
    end
  end

  boss "Stormwatcher" do
    boss_id 70202
    health 2_500_000
    level 25
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "The storms obey my will!"

      ability :lightning_bolt, cooldown: 5_000, target: :tank do
        damage 11000, type: :magic
      end

      ability :thunder_strike, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 1800, color: :blue
        damage 9000, type: :magic
        coordination :spread, damage: 15000, min_distance: 6
      end

      ability :wind_shear, cooldown: 15_000 do
        telegraph :cone, angle: 60, length: 20, duration: 2000, color: :blue
        damage 10000, type: :magic
        movement :knockback, distance: 8
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "WITNESS THE STORM'S FURY!"
      enrage_modifier 1.35

      ability :tempest, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 14000, type: :magic
      end

      ability :summon_elementals, cooldown: 28_000 do
        spawn :add, creature_id: 70221, count: 3, spread: true
      end
    end

    on_death do
      loot_table 70202
    end
  end

  boss "Siege Commander" do
    boss_id 70203
    health 3_000_000
    level 25
    enrage_timer 360_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "The refuge will fall!"

      ability :commander_strike, cooldown: 5_000, target: :tank do
        damage 13000, type: :physical
      end

      ability :rally_troops, cooldown: 25_000 do
        spawn :add, creature_id: 70231, count: 3, spread: true
        buff :commander_aura, duration: 15000
      end

      ability :siege_barrage, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 11000, type: :physical
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "ALL FORCES, ATTACK!"
      enrage_modifier 1.35

      ability :artillery_strike, cooldown: 22_000 do
        telegraph :circle, radius: 6, duration: 1500, color: :red
        damage 14000, type: :fire
        spawn :add, creature_id: 70232, count: 2, spread: true
      end

      ability :tactical_sweep, cooldown: 15_000 do
        telegraph :cone, angle: 120, length: 22, duration: 2000, color: :red
        damage 12000, type: :physical
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "I WILL NOT FAIL!"
      enrage_modifier 1.6

      ability :final_assault, cooldown: 25_000 do
        telegraph :room_wide, duration: 4000
        damage 20000, type: :physical
      end

      ability :desperate_measures, cooldown: 20_000 do
        buff :berserk, duration: 15000
        buff :damage_increase, duration: 15000
      end
    end

    on_death do
      loot_table 70203
      achievement 7020  # Siege completion
    end
  end
end
