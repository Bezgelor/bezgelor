defmodule BezgelorWorld.Encounter.Bosses.WorldBosses.KingHoneygrave do
  @moduledoc """
  King Honeygrave - World Boss in Auroria.
  Giant buzzbing monarch requiring 20+ players.
  """

  use BezgelorWorld.Encounter.DSL

  boss "King Honeygrave" do
    boss_id 80002
    health 55_000_000
    level 30
    enrage_timer 900_000
    interrupt_armor 6

    phase :one, health_above: 70 do
      phase_emote "*ANGRY BUZZING*"

      ability :stinger_strike, cooldown: 5_000, target: :tank do
        damage 48000, type: :nature
        debuff :poisoned, duration: 12000, stacks: 2
      end

      ability :honey_bomb, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 10, duration: 2000, color: :yellow
        damage 35000, type: :nature
        debuff :slowed, duration: 8000
      end

      ability :swarm_call, cooldown: 25_000 do
        spawn :add, creature_id: 80021, count: 8, spread: true
      end

      ability :wing_buffet, cooldown: 15_000 do
        telegraph :cone, angle: 120, length: 30, duration: 2000, color: :yellow
        damage 30000, type: :physical
        movement :knockback, distance: 12
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase :one
      phase_emote "*FURIOUS BUZZING*"
      enrage_modifier 1.35

      ability :royal_decree, cooldown: 30_000 do
        spawn :add, creature_id: 80022, count: 4, spread: true
        buff :royal_fury, duration: 15000
      end

      ability :pollen_storm, cooldown: 35_000 do
        telegraph :room_wide, duration: 5000
        damage 45000, type: :nature
        debuff :poisoned, duration: 15000, stacks: 3
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "*DEAFENING BUZZING*"
      enrage_modifier 1.6

      ability :apocalyptic_swarm, cooldown: 35_000 do
        telegraph :room_wide, duration: 6000
        damage 65000, type: :nature
      end

      ability :mass_swarm, cooldown: 25_000 do
        spawn :add, creature_id: 80023, count: 12, spread: true
      end
    end

    on_death do
      loot_table 80002
      achievement 8002  # King Honeygrave Slayer
    end
  end
end
