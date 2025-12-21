defmodule BezgelorWorld.Encounter.Bosses.StormtalonsLair.BladewindTheInvoker do
  @moduledoc """
  Blade-Wind the Invoker encounter - Stormtalon's Lair (First Boss)

  A Pell sorcerer who channels the power of Stormtalon. Features:
  - Cross-shaped lightning attacks (Thunder Cross)
  - Pulsing AoE damage (Electrostatic Pulse)
  - Channeler add phase requiring interrupt/kill coordination

  ## Strategy
  Phase 1 (100-75%): Avoid Thunder Cross, stay spread for Electrostatic Pulse
  Phase 2 (75-50%): Kill Thundercall Channelers to break invulnerability
  Phase 3 (50-25%): Increased ability frequency, dodge Static Wave
  Phase 4 (<25%): Burn phase with enrage mechanics

  Data sources: client_data, wiki, achievement text
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Blade-Wind the Invoker" do
    boss_id(17160)
    health(400_000)
    level(20)
    enrage_timer(480_000)
    interrupt_armor(2)

    # Phase 1: 100% - 75% health - Introduction
    phase :one, health_above: 75 do
      phase_emote("You dare shed the blood of Stormtalon's disciples?")

      ability :thunder_cross, cooldown: 20_000, target: :random do
        telegraph(:cross, width: 3, length: 20, duration: 2500, color: :red)
        damage(8000, type: :magic)
      end

      ability :electrostatic_pulse, cooldown: 15_000 do
        telegraph(:circle, radius: 8, duration: 2000, color: :blue)
        damage(5000, type: :magic)
      end

      ability :lightning_bolt, cooldown: 8_000, target: :tank do
        damage(4000, type: :magic)
        debuff(:conductivity, duration: 8000, stacks: 1)
      end
    end

    # Phase 2: 75% - 50% health - Channeler Phase
    phase :two, health_between: {50, 75} do
      inherit_phase(:one)
      phase_emote("Disciples of Stormtalon! Channel the ancient powers!")

      ability :summon_channelers, cooldown: 45_000 do
        spawn(:add, creature_id: 17161, count: 4, spread: true)
        buff(:storm_shield, duration: 30_000)
      end

      ability :static_wave, cooldown: 12_000 do
        telegraph(:line, width: 4, length: 25, duration: 2000, color: :red)
        damage(6000, type: :magic)
        movement(:knockback, distance: 8)
      end
    end

    # Phase 3: 50% - 25% health - Intensified
    phase :three, health_between: {25, 50} do
      inherit_phase(:two)
      phase_emote("The storm answers my call!")

      ability :chain_lightning, cooldown: 18_000, target: :random do
        damage(4500, type: :magic)
        coordination(:spread, required_distance: 6, damage: 5000)
      end

      ability :thunder_cross_double, cooldown: 25_000 do
        telegraph(:cross, width: 3, length: 20, duration: 2000, color: :red)
        damage(9000, type: :magic)
      end
    end

    # Phase 4: Below 25% health - Enrage
    phase :four, health_below: 25 do
      inherit_phase(:three)
      phase_emote("Feel the wrath of the storm!")
      enrage_modifier(1.3)

      ability :lightning_storm, cooldown: 20_000 do
        telegraph(:room_wide, duration: 3000)
        damage(6000, type: :magic)
        safe_zone(shape: :circle, radius: 5, position: :boss)
      end
    end

    on_death do
      loot_table(17160)
      # "Who's Afraid of the Big Bad Wolf?" (placeholder)
      achievement(6701)
    end
  end
end
