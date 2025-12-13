defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.MetalMawPrime do
  @moduledoc """
  Metal Maw Prime - World Boss in Galeras.
  Massive mechanical construct requiring 20+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Metal Maw Prime" do
    boss_id 80001
    health 50_000_000
    level 25
    enrage_timer 900_000
    interrupt_armor 6

    phase :one, health_above: 70 do
      phase_emote "SYSTEMS ONLINE. THREAT DETECTED. INITIATING EXTERMINATION."

      ability :metal_crush, cooldown: 5_000, target: :tank do
        damage 45000, type: :physical
        debuff :armor_break, duration: 10000, stacks: 1
      end

      ability :laser_barrage, cooldown: 12_000, target: :random do
        telegraph :line, width: 6, length: 40, duration: 2000, color: :red
        damage 35000, type: :magic
        coordination :spread, damage: 60000, min_distance: 10
      end

      ability :stomp, cooldown: 15_000 do
        telegraph :circle, radius: 20, duration: 2500, color: :brown
        damage 30000, type: :physical
        movement :knockback, distance: 15
      end

      ability :deploy_drones, cooldown: 30_000 do
        spawn :add, creature_id: 80011, count: 6, spread: true
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase :one
      phase_emote "COMBAT PROTOCOLS ESCALATING."
      enrage_modifier 1.35

      ability :orbital_strike, cooldown: 25_000 do
        telegraph :circle, radius: 12, duration: 3000, color: :red
        damage 50000, type: :fire
      end

      ability :system_overload, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 45000, type: :magic
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "MAXIMUM THREAT RESPONSE ACTIVATED."
      enrage_modifier 1.6

      ability :apocalypse_protocol, cooldown: 40_000 do
        telegraph :room_wide, duration: 6000
        damage 70000, type: :magic
      end

      ability :mass_deployment, cooldown: 30_000 do
        spawn :add, creature_id: 80012, count: 10, spread: true
      end
    end

    on_death do
      loot_table 80001
      achievement 8001  # Metal Maw Prime Slayer
    end
  end
end
