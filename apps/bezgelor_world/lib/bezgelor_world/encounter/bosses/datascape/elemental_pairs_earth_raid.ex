defmodule BezgelorWorld.Encounter.Bosses.Datascape.ElementalPairsEarthRaid do
  @moduledoc """
  Elemental Pairs: Earth encounter - Datascape (Fifth Boss - 40-man Raid)

  One of four elemental pairs that must be killed within 20 seconds of each other.
  Earth element features heavy physical damage and ground-based mechanics. Features:
  - Earthquake room-wide requiring movement
  - Fissure line attacks splitting the arena
  - Landslide cone knockback
  - Rock Golem adds with high health

  ## Strategy
  Phase 1 (100-50%): Tank in center, dodge Fissure lines
  Phase 2 (<50%): Handle Landslide positioning, kill Golems quickly
  IMPORTANT: Must kill within 20 seconds of Life element or both heal to full

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Elemental Pairs - Earth" do
    boss_id(70005)
    health(100_000_000)
    level(50)
    enrage_timer(720_000)
    interrupt_armor(5)

    phase :one, health_above: 50 do
      phase_emote("THE EARTH TREMBLES!")

      ability :boulder_smash, cooldown: 10_000, target: :tank do
        damage(70000, type: :physical)
        debuff(:crushed, duration: 10000, stacks: 1)
      end

      ability :fissure, cooldown: 15_000 do
        telegraph(:line, width: 8, length: 40, duration: 2500, color: :brown)
        damage(50000, type: :physical)
        debuff(:unstable_ground, duration: 8000)
      end

      ability :earthquake, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(40000, type: :physical)
        movement(:knockback, distance: 5, source: :center)
      end

      ability :rock_wall, cooldown: 20_000 do
        telegraph(:line, width: 5, length: 30, duration: 2000, color: :brown)
        damage(35000, type: :physical)
      end

      ability :stone_spike, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 6, duration: 1500, color: :brown)
        damage(45000, type: :physical)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("FEEL THE MOUNTAIN'S FURY!")
      enrage_modifier(1.4)

      ability :landslide, cooldown: 20_000 do
        telegraph(:cone, angle: 90, length: 35, duration: 3000, color: :brown)
        damage(65000, type: :physical)
        movement(:knockback, distance: 15)
      end

      ability :spawn_golems, cooldown: 40_000 do
        spawn(:add, creature_id: 70052, count: 4, spread: true)
      end

      ability :tectonic_shift, cooldown: 35_000 do
        telegraph(:room_wide, duration: 5000)
        damage(60000, type: :physical)
        debuff(:tectonic_instability, duration: 12000, stacks: 1)
      end

      ability :mountain_crush, cooldown: 25_000 do
        telegraph(:circle, radius: 15, duration: 2500, color: :brown)
        damage(55000, type: :physical)
        movement(:pull, distance: 10)
      end

      ability :earthen_fury, cooldown: 30_000 do
        telegraph(:cross, length: 35, width: 8, duration: 3000, color: :brown)
        damage(60000, type: :physical)
      end

      ability :stone_form, cooldown: 45_000 do
        buff(:stone_armor, duration: 10000)
        buff(:damage_reduction, duration: 10000)
      end
    end

    on_death do
      loot_table(70005)
    end
  end
end
