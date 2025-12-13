defmodule BezgelorWorld.Encounter.Bosses.VeteranSanctuarySwordmaiden.MoldwoodOverlordVeteran do
  @moduledoc """
  Moldwood Overlord (Veteran) - Veteran Sanctuary of the Swordmaiden (Third Boss)

  Enhanced fungal corruption encounter with poison mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Moldwood Overlord (Veteran)" do
    boss_id 50803
    health 4_400_000
    level 50
    enrage_timer 540_000
    interrupt_armor 4

    phase :one, health_above: 55 do
      phase_emote "The corruption spreads!"

      ability :fungal_strike, cooldown: 10_000, target: :tank do
        damage 22000, type: :nature
        debuff :infected, duration: 12000, stacks: 1
      end

      ability :spore_cloud, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 12, duration: 2000, color: :green
        damage 14000, type: :poison
        debuff :spored, duration: 8000, stacks: 1
      end

      ability :rot_wave, cooldown: 18_000 do
        telegraph :cone, angle: 90, length: 25, duration: 2500, color: :green
        damage 18000, type: :poison
      end

      ability :spawn_funglings, cooldown: 25_000 do
        spawn :add, creature_id: 50832, count: 4, spread: true
      end
    end

    phase :two, health_below: 55 do
      inherit_phase :one
      phase_emote "ALL WILL ROT!"
      enrage_modifier 1.4

      ability :corruption_burst, cooldown: 30_000 do
        telegraph :room_wide, duration: 4500
        damage 16000, type: :poison
        debuff :corrupted, duration: 15000, stacks: 2
      end

      ability :fungal_explosion, cooldown: 22_000 do
        telegraph :circle, radius: 18, duration: 3000, color: :green
        damage 20000, type: :poison
        movement :knockback, distance: 10
      end

      ability :spreading_rot, cooldown: 25_000, target: :random do
        telegraph :circle, radius: 6, duration: 2500, color: :green
        coordination :spread, min_distance: 8, damage: 18000
      end

      ability :final_corruption, cooldown: 40_000 do
        buff :corrupting, duration: 15000
        spawn :add, creature_id: 50832, count: 6, spread: true
      end
    end

    on_death do
      loot_table 50803
    end
  end
end
