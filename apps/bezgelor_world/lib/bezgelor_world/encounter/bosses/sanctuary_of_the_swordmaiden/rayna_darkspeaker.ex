defmodule BezgelorWorld.Encounter.Bosses.SanctuaryOfTheSwordmaiden.RaynaDarkspeaker do
  @moduledoc """
  Rayna Darkspeaker encounter - Sanctuary of the Swordmaiden (First Boss)

  A shadow priestess who commands darkness. Features:
  - Shadow bolt volleys targeting random players
  - Shadow clones that mirror her abilities
  - Enveloping Darkness room-wide requiring healing cooldowns
  - Shadow Link mechanic requiring players to spread

  ## Strategy
  Phase 1 (100-50%): Spread loosely, dodge shadow bolts and novas
  Phase 2 (<50%): Kill clones quickly, spread for Shadow Link, cooldowns for Darkness

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Rayna Darkspeaker" do
    boss_id(50301)
    health(1_600_000)
    level(35)
    enrage_timer(420_000)
    interrupt_armor(2)

    phase :one, health_above: 50 do
      phase_emote("The shadows hunger for your souls!")

      ability :shadow_bolt, cooldown: 5_000, target: :random do
        telegraph(:circle, radius: 4, duration: 1000, color: :purple)
        damage(4000, type: :magic)
      end

      ability :dark_nova, cooldown: 15_000 do
        telegraph(:circle, radius: 10, duration: 2000, color: :purple)
        damage(6000, type: :magic)
        debuff(:shadow_touched, duration: 6000, stacks: 1)
      end

      ability :shadow_strike, cooldown: 8_000, target: :tank do
        damage(5000, type: :magic)
        debuff(:shadow_wound, duration: 6000, stacks: 1)
      end

      ability :creeping_shadows, cooldown: 12_000, target: :random do
        telegraph(:cone, angle: 45, length: 18, duration: 1500, color: :purple)
        damage(4500, type: :magic)
        debuff(:slowed, duration: 4000)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("Rise, my shadows! Consume them!")
      enrage_modifier(1.25)

      ability :shadow_clone, cooldown: 25_000 do
        spawn(:add, creature_id: 50311, count: 2, spread: true)
      end

      ability :enveloping_darkness, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4000)
        damage(5000, type: :magic)
        debuff(:blinded, duration: 5000)
      end

      ability :shadow_link, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 5, duration: 2000, color: :purple)
        coordination(:spread, min_distance: 8, damage: 12000)
      end

      ability :void_eruption, cooldown: 18_000 do
        telegraph(:circle, radius: 8, duration: 2000, color: :purple)
        damage(7000, type: :magic)
        movement(:knockback, distance: 6)
      end

      ability :shadow_barrage, cooldown: 22_000 do
        telegraph(:circle, radius: 5, duration: 1200, color: :purple)
        damage(4000, type: :magic)
        spawn(:add, creature_id: 50317, count: 4, spread: true)
      end
    end

    on_death do
      loot_table(50301)
    end
  end
end
