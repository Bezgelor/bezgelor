defmodule BezgelorWorld.Encounter.Bosses.VeteranAdventures.VeteranMalgraveTrail do
  @moduledoc """
  Veteran Malgrave Trail adventure bosses.
  Enhanced difficulty with additional mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Scorchwing (Veteran)" do
    boss_id(71101)
    health(5_500_000)
    level(50)
    enrage_timer(420_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("THE DESERT BURNS WITH MY FURY!")

      ability :flame_breath, cooldown: 5_000, target: :tank do
        damage(28000, type: :fire)
        debuff(:burning, duration: 10000, stacks: 2)
      end

      ability :dive_bomb, cooldown: 12_000, target: :random do
        telegraph(:circle, radius: 10, duration: 1800, color: :red)
        damage(32000, type: :physical)
        coordination(:spread, damage: 50000, min_distance: 8)
      end

      ability :wing_buffet, cooldown: 10_000 do
        telegraph(:cone, angle: 120, length: 25, duration: 1800, color: :orange)
        damage(25000, type: :fire)
        movement(:knockback, distance: 12)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("NOTHING ESCAPES THE INFERNO!")
      enrage_modifier(1.4)

      ability :firestorm, cooldown: 22_000 do
        telegraph(:room_wide, duration: 4000)
        damage(38000, type: :fire)
      end

      ability :summon_hatchlings, cooldown: 25_000 do
        spawn(:add, creature_id: 71111, count: 4, spread: true)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("BURN! BURN IT ALL!")
      enrage_modifier(1.7)

      ability :apocalyptic_flame, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4500)
        damage(48000, type: :fire)
      end

      ability :phoenix_rebirth, cooldown: 30_000 do
        buff(:phoenix_form, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    on_death do
      loot_table(71101)
    end
  end

  boss "Hellrose (Veteran)" do
    boss_id(71102)
    health(6_500_000)
    level(50)
    enrage_timer(480_000)
    interrupt_armor(3)

    phase :one, health_above: 60 do
      phase_emote("The thorns hunger for blood!")

      ability :thorn_strike, cooldown: 5_000, target: :tank do
        damage(32000, type: :nature)
        debuff(:bleeding, duration: 10000, stacks: 2)
      end

      ability :poison_spray, cooldown: 10_000 do
        telegraph(:cone, angle: 75, length: 28, duration: 1800, color: :green)
        damage(26000, type: :nature)
        debuff(:poisoned, duration: 12000, stacks: 2)
      end

      ability :root_trap, cooldown: 15_000, target: :random do
        telegraph(:circle, radius: 8, duration: 1800, color: :green)
        damage(22000, type: :nature)
        debuff(:rooted, duration: 5000)
        coordination(:spread, damage: 40000, min_distance: 6)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("THE JUNGLE CONSUMES!")
      enrage_modifier(1.4)

      ability :spawn_seedlings, cooldown: 22_000 do
        spawn(:add, creature_id: 71121, count: 5, spread: true)
      end

      ability :toxic_bloom, cooldown: 25_000 do
        telegraph(:room_wide, duration: 4000)
        damage(35000, type: :nature)
        debuff(:poisoned, duration: 15000, stacks: 3)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("ALL FLESH BECOMES FERTILIZER!")
      enrage_modifier(1.7)

      ability :nature_apocalypse, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4500)
        damage(45000, type: :nature)
      end

      ability :thorn_cross, cooldown: 18_000 do
        telegraph(:cross, length: 32, width: 6, duration: 2000, color: :green)
        damage(38000, type: :nature)
      end
    end

    on_death do
      loot_table(71102)
    end
  end

  boss "Canimid Alpha (Veteran)" do
    boss_id(71103)
    health(8_000_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(4)

    phase :one, health_above: 70 do
      phase_emote("*thunderous howl*")

      ability :savage_bite, cooldown: 5_000, target: :tank do
        damage(35000, type: :physical)
        debuff(:bleeding, duration: 12000, stacks: 3)
      end

      ability :pack_howl, cooldown: 12_000 do
        telegraph(:circle, radius: 18, duration: 2000, color: :brown)
        damage(25000, type: :physical)
        buff(:pack_fury, duration: 12000)
      end

      ability :pounce, cooldown: 10_000, target: :farthest do
        telegraph(:line, width: 5, length: 35, duration: 1500, color: :red)
        damage(30000, type: :physical)
        debuff(:stunned, duration: 2000)
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase(:one)
      phase_emote("*rallying pack cry*")
      enrage_modifier(1.35)

      ability :call_pack, cooldown: 22_000 do
        spawn(:add, creature_id: 71131, count: 5, spread: true)
      end

      ability :frenzy, cooldown: 28_000 do
        buff(:frenzied, duration: 15000)
        buff(:damage_increase, duration: 15000)
      end
    end

    phase :three, health_below: 40 do
      inherit_phase(:two)
      phase_emote("*primal rage*")
      enrage_modifier(1.6)

      ability :alpha_rampage, cooldown: 20_000 do
        telegraph(:room_wide, duration: 4000)
        damage(45000, type: :physical)
      end

      ability :death_grip, cooldown: 15_000, target: :healer do
        movement(:pull, distance: 20)
        damage(28000, type: :physical)
        coordination(:stack, damage: 60000, required_players: 3)
      end
    end

    on_death do
      loot_table(71103)
      # Veteran Malgrave Trail completion
      achievement(7110)
    end
  end
end
