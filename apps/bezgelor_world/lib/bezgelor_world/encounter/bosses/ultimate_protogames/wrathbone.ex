defmodule BezgelorWorld.Encounter.Bosses.UltimateProtogames.Wrathbone do
  @moduledoc """
  Wrathbone encounter - Ultimate Protogames (First Boss)

  A massive skeletal champion in the Protogames arena. Features:
  - Physical damage focused attacks
  - Bone Spikes random targeting
  - Skeletal Charge knockback
  - Bone Storm room-wide in phase 2

  ## Strategy
  Phase 1 (100-50%): Tank and spank, avoid Bone Spikes
  Phase 2 (<50%): Kill skeleton adds, survive Bone Storm

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Wrathbone" do
    boss_id(50401)
    health(2_200_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("WRATHBONE SMASH PUNY CONTESTANTS!")

      ability :bone_crush, cooldown: 8_000, target: :tank do
        damage(12000, type: :physical)
        debuff(:crushed_bones, duration: 8000, stacks: 1)
      end

      ability :ground_pound, cooldown: 12_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :brown)
        damage(8000, type: :physical)
        movement(:knockback, distance: 6)
      end

      ability :skeletal_charge, cooldown: 18_000, target: :farthest do
        telegraph(:line, width: 5, length: 30, duration: 2000, color: :brown)
        damage(10000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :bone_spikes, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 6, duration: 1500, color: :brown)
        damage(7000, type: :physical)
      end

      ability :rattle, cooldown: 20_000 do
        telegraph(:circle, radius: 12, duration: 1800, color: :brown)
        damage(6000, type: :physical)
        debuff(:rattled, duration: 5000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("WRATHBONE GETTING ANGRY NOW!")
      enrage_modifier(1.3)

      ability :bone_storm, cooldown: 25_000 do
        telegraph(:room_wide, duration: 3500)
        damage(9000, type: :physical)
        debuff(:storm_battered, duration: 8000, stacks: 1)
      end

      ability :summon_skeletons, cooldown: 30_000 do
        spawn(:add, creature_id: 50412, count: 4, spread: true)
      end

      ability :enraged_smash, cooldown: 20_000 do
        telegraph(:cone, angle: 120, length: 15, duration: 2500, color: :red)
        damage(12000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :bone_cage, cooldown: 35_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :brown)
        debuff(:caged, duration: 4000)
        damage(5000, type: :physical)
      end

      ability :final_rampage, cooldown: 45_000 do
        buff(:rampaging, duration: 10000)
        buff(:damage_increase, duration: 10000)
      end
    end

    on_death do
      loot_table(50401)
    end
  end
end
