defmodule BezgelorWorld.Encounter.Bosses.SanctuaryOfTheSwordmaiden.MoldwoodOverlord do
  @moduledoc """
  Moldwood Overlord encounter - Sanctuary of the Swordmaiden (Optional Boss)

  A fungal giant that spreads toxic spores. Features:
  - Spore Cloud ground hazards with stacking poison
  - Root Grasp CC requiring dispels
  - Toxic Spores room-wide in enrage
  - Fungal Growth spawns small adds

  ## Strategy
  Phase 1 (100-50%): Stay mobile, dispel roots, avoid spore clouds
  Phase 2 (<50%): Stack for heals during Toxic Spores, kill fungal adds

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Moldwood Overlord" do
    boss_id(50303)
    health(1_400_000)
    level(35)
    enrage_timer(360_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("The forest reclaims what is hers...")

      ability :spore_cloud, cooldown: 12_000 do
        telegraph(:circle, radius: 8, duration: 2000, color: :green)
        damage(4000, type: :poison)
        debuff(:spored, duration: 8000, stacks: 1)
      end

      ability :root_grasp, cooldown: 18_000, target: :random do
        telegraph(:circle, radius: 5, duration: 1500, color: :green)
        debuff(:rooted, duration: 4000)
        damage(3000, type: :physical)
      end

      ability :fungal_slam, cooldown: 8_000, target: :tank do
        telegraph(:cone, angle: 90, length: 10, duration: 1500, color: :green)
        damage(6000, type: :physical)
      end

      ability :decompose, cooldown: 15_000, target: :random do
        damage(3500, type: :poison)
        debuff(:decomposing, duration: 10000, stacks: 2)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("DECAY! BECOME ONE WITH THE FOREST!")
      enrage_modifier(1.3)

      ability :toxic_spores, cooldown: 25_000 do
        telegraph(:room_wide, duration: 3000)
        damage(5000, type: :poison)
        debuff(:poisoned, duration: 10000, stacks: 2)
      end

      ability :fungal_growth, cooldown: 20_000 do
        spawn(:add, creature_id: 50314, count: 3, spread: true)
      end

      ability :spore_burst, cooldown: 15_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :green)
        damage(6000, type: :poison)
        movement(:knockback, distance: 8)
      end

      ability :mass_root, cooldown: 30_000 do
        telegraph(:room_wide, duration: 2500)
        debuff(:rooted, duration: 3000)
        damage(4000, type: :physical)
      end

      ability :overwhelming_stench, cooldown: 22_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :green)
        damage(5000, type: :poison)
        debuff(:weakened, duration: 8000, stacks: 1)
      end
    end

    on_death do
      loot_table(50303)
    end
  end
end
