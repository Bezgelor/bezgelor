defmodule BezgelorWorld.Encounter.Bosses.Adventures.MalgraveTrail do
  @moduledoc """
  The Malgrave Trail adventure bosses.
  Caravan escort through hostile desert territory.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Scorchwing" do
    boss_id 70101
    health 2_500_000
    level 35
    enrage_timer 300_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "SCREEEECH! Intruders in my hunting grounds!"

      ability :flame_breath, cooldown: 6_000, target: :tank do
        damage 12000, type: :fire
        debuff :burning, duration: 8000, stacks: 1
      end

      ability :dive_bomb, cooldown: 15_000, target: :random do
        telegraph :circle, radius: 8, duration: 2000, color: :red
        damage 15000, type: :physical
      end

      ability :wing_buffet, cooldown: 12_000 do
        telegraph :cone, angle: 90, length: 20, duration: 1800, color: :orange
        damage 10000, type: :fire
        movement :knockback, distance: 8
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "THE DESERT BURNS!"
      enrage_modifier 1.35

      ability :firestorm, cooldown: 25_000 do
        telegraph :room_wide, duration: 3500
        damage 18000, type: :fire
      end

      ability :summon_hatchlings, cooldown: 30_000 do
        spawn :add, creature_id: 70111, count: 3, spread: true
      end
    end

    on_death do
      loot_table 70101
    end
  end

  boss "Hellrose" do
    boss_id 70102
    health 3_000_000
    level 35
    enrage_timer 360_000
    interrupt_armor 2

    phase :one, health_above: 50 do
      phase_emote "The desert claims all who trespass..."

      ability :thorn_strike, cooldown: 6_000, target: :tank do
        damage 14000, type: :nature
        debuff :bleeding, duration: 8000, stacks: 1
      end

      ability :poison_spray, cooldown: 12_000 do
        telegraph :cone, angle: 60, length: 22, duration: 1800, color: :green
        damage 11000, type: :nature
        debuff :poisoned, duration: 10000, stacks: 1
      end

      ability :root_trap, cooldown: 18_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :green
        damage 9000, type: :nature
        debuff :rooted, duration: 4000
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "NATURE RECLAIMS ALL!"
      enrage_modifier 1.4

      ability :spawn_seedlings, cooldown: 25_000 do
        spawn :add, creature_id: 70121, count: 4, spread: true
      end

      ability :toxic_bloom, cooldown: 28_000 do
        telegraph :room_wide, duration: 3500
        damage 16000, type: :nature
        debuff :poisoned, duration: 12000, stacks: 2
      end
    end

    on_death do
      loot_table 70102
    end
  end

  boss "Canimid Alpha" do
    boss_id 70103
    health 3_500_000
    level 35
    enrage_timer 420_000
    interrupt_armor 3

    phase :one, health_above: 60 do
      phase_emote "*menacing growl*"

      ability :savage_bite, cooldown: 5_000, target: :tank do
        damage 16000, type: :physical
        debuff :bleeding, duration: 10000, stacks: 2
      end

      ability :pack_howl, cooldown: 15_000 do
        telegraph :circle, radius: 15, duration: 2000, color: :brown
        damage 10000, type: :physical
        buff :pack_fury, duration: 10000
      end

      ability :pounce, cooldown: 12_000, target: :farthest do
        telegraph :line, width: 4, length: 25, duration: 1500, color: :red
        damage 14000, type: :physical
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase :one
      phase_emote "*rallying howl*"
      enrage_modifier 1.35

      ability :call_pack, cooldown: 25_000 do
        spawn :add, creature_id: 70131, count: 4, spread: true
      end

      ability :frenzy, cooldown: 30_000 do
        buff :frenzied, duration: 12000
        buff :damage_increase, duration: 12000
      end
    end

    phase :three, health_below: 30 do
      inherit_phase :two
      phase_emote "*enraged roar*"
      enrage_modifier 1.6

      ability :alpha_rampage, cooldown: 22_000 do
        telegraph :room_wide, duration: 3500
        damage 22000, type: :physical
      end

      ability :death_grip, cooldown: 18_000, target: :healer do
        movement :pull, distance: 15
        damage 12000, type: :physical
      end
    end

    on_death do
      loot_table 70103
      achievement 7010  # Malgrave Trail completion
    end
  end
end
