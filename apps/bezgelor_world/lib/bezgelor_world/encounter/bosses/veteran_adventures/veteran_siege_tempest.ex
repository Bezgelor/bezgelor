defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranSiegeTempest do
  @moduledoc """
  Veteran Siege of Tempest Refuge adventure bosses.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Skullcrusher (Veteran)" do
    boss_id(71201)
    health(5_000_000)
    level(50)
    enrage_timer(360_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("CRUSH ALL DEFENDERS!")

      ability :skull_bash, cooldown: 5_000, target: :tank do
        damage(28000, type: :physical)
        debuff(:dazed, duration: 4000)
      end

      ability :ground_slam, cooldown: 10_000 do
        telegraph(:circle, radius: 14, duration: 2000, color: :brown)
        damage(22000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :war_cry, cooldown: 18_000 do
        buff(:war_fury, duration: 12000)
        spawn(:add, creature_id: 71211, count: 3, spread: true)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("THE SIEGE CANNOT BE STOPPED!")
      enrage_modifier(1.4)

      ability :rampage, cooldown: 22_000 do
        telegraph(:line, width: 8, length: 30, duration: 2000, color: :red)
        damage(35000, type: :physical)
      end

      ability :siege_call, cooldown: 25_000 do
        spawn(:add, creature_id: 71212, count: 5, spread: true)
      end

      ability :devastating_blow, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(40000, type: :physical)
      end
    end

    on_death do
      loot_table(71201)
    end
  end

  boss "Stormwatcher (Veteran)" do
    boss_id(71202)
    health(5_800_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 50 do
      phase_emote("THE STORM OBEYS MY COMMAND!")

      ability :lightning_bolt, cooldown: 5_000, target: :tank do
        damage(30000, type: :magic)
      end

      ability :thunder_strike, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :blue)
        damage(25000, type: :magic)
        coordination(:spread, damage: 45000, min_distance: 8)
      end

      ability :wind_shear, cooldown: 12_000 do
        telegraph(:cone, angle: 75, length: 25, duration: 2000, color: :blue)
        damage(28000, type: :magic)
        movement(:knockback, distance: 12)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("WITNESS THE STORM'S TRUE POWER!")
      enrage_modifier(1.45)

      ability :tempest, cooldown: 22_000 do
        telegraph(:room_wide, duration: 4000)
        damage(38000, type: :magic)
      end

      ability :summon_elementals, cooldown: 25_000 do
        spawn(:add, creature_id: 71221, count: 4, spread: true)
      end

      ability :chain_lightning, cooldown: 18_000 do
        telegraph(:line, width: 4, length: 35, duration: 1500, color: :blue)
        damage(32000, type: :magic)
      end
    end

    on_death do
      loot_table(71202)
    end
  end

  boss "Siege Commander (Veteran)" do
    boss_id(71203)
    health(7_000_000)
    level(50)
    enrage_timer(480_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("THE REFUGE WILL FALL!")

      ability :commander_strike, cooldown: 5_000, target: :tank do
        damage(32000, type: :physical)
      end

      ability :rally_troops, cooldown: 22_000 do
        spawn(:add, creature_id: 71231, count: 4, spread: true)
        buff(:commander_aura, duration: 18000)
      end

      ability :siege_barrage, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 10, duration: 2000, color: :red)
        damage(28000, type: :physical)
        coordination(:spread, damage: 50000, min_distance: 8)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("ALL FORCES, MAXIMUM ASSAULT!")
      enrage_modifier(1.4)

      ability :artillery_strike, cooldown: 18_000 do
        telegraph(:circle, radius: 8, duration: 1500, color: :red)
        damage(35000, type: :fire)
        spawn(:add, creature_id: 71232, count: 3, spread: true)
      end

      ability :tactical_sweep, cooldown: 12_000 do
        telegraph(:cone, angle: 150, length: 25, duration: 2000, color: :red)
        damage(30000, type: :physical)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("VICTORY OR DEATH!")
      enrage_modifier(1.7)

      ability :final_assault, cooldown: 22_000 do
        telegraph(:room_wide, duration: 4500)
        damage(48000, type: :physical)
      end

      ability :desperate_measures, cooldown: 18_000 do
        buff(:berserk, duration: 18000)
        buff(:damage_increase, duration: 18000)
      end
    end

    on_death do
      loot_table(71203)
      # Veteran Siege completion
      achievement(7120)
    end
  end
end
