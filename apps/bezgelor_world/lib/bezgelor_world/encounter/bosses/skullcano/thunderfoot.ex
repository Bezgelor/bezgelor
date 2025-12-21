defmodule BezgelorWorld.Encounter.Bosses.Skullcano.Thunderfoot do
  @moduledoc """
  Thunderfoot encounter - Skullcano (Second Boss)

  A massive mammoth beast that shakes the cavern with seismic attacks. Features:
  - Heavy ground-based AoE requiring constant movement
  - Charge mechanic targeting farthest player
  - Earthquake room-wide damage in enrage phase
  - Rampage mode with increased attack speed

  ## Strategy
  Phase 1 (100-40%): Tank kites boss, ranged stay at medium distance for charge
  Phase 2 (<40%): Stack for heals during Earthquake, burn boss before Rampage stacks

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Thunderfoot" do
    boss_id(50202)
    health(1_800_000)
    level(30)
    enrage_timer(420_000)
    interrupt_armor(3)

    # Phase 1: 100% - 40% health - Territorial Rage
    phase :one, health_above: 40 do
      phase_emote("*THUNDEROUS ROAR* The beast awakens!")

      ability :stomp, cooldown: 10_000 do
        telegraph(:circle, radius: 10, duration: 1800, color: :red)
        damage(6000, type: :physical)
        debuff(:stunned, duration: 2000)
      end

      ability :charge, cooldown: 15_000, target: :farthest do
        telegraph(:line, width: 5, length: 30, duration: 1500, color: :red)
        damage(7000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :ground_slam, cooldown: 8_000, target: :tank do
        telegraph(:cone, angle: 90, length: 12, duration: 1500, color: :red)
        damage(8000, type: :physical)
      end

      ability :tusk_gore, cooldown: 6_000, target: :tank do
        damage(6500, type: :physical)
        debuff(:bleeding, duration: 8000, stacks: 1)
      end

      ability :shake_off, cooldown: 20_000 do
        telegraph(:circle, radius: 8, duration: 1200, color: :red)
        damage(4000, type: :physical)
        movement(:knockback, distance: 12)
      end
    end

    # Phase 2: Below 40% health - Rampage
    phase :two, health_below: 40 do
      inherit_phase(:one)
      phase_emote("*ENRAGED BELLOWING* THUNDERFOOT ANGRY!")
      enrage_modifier(1.3)

      ability :earthquake, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(5000, type: :physical)
        movement(:knockback, distance: 5, source: :center)
      end

      ability :rampage, cooldown: 45_000 do
        buff(:enraged, duration: 15000)
        buff(:rampage_speed, duration: 15000)
      end

      ability :aftershock, cooldown: 12_000 do
        telegraph(:circle, radius: 15, duration: 2000, color: :red)
        damage(7000, type: :physical)
        debuff(:dazed, duration: 3000)
      end

      ability :fury_charge, cooldown: 18_000, target: :random do
        telegraph(:line, width: 6, length: 35, duration: 1200, color: :red)
        damage(9000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :seismic_slam, cooldown: 22_000 do
        telegraph(:donut, inner_radius: 5, outer_radius: 20, duration: 2500, color: :red)
        damage(8000, type: :physical)
      end

      ability :frenzy_stomp, cooldown: 30_000 do
        telegraph(:circle, radius: 12, duration: 1500, color: :red)
        damage(6000, type: :physical)
        spawn(:add, creature_id: 50221, count: 2, spread: true)
      end
    end

    on_death do
      loot_table(50202)
    end
  end
end
