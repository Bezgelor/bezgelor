defmodule BezgelorWorld.Encounter.Bosses.PrimeKelVoreth.GrondTheCorpsemakerPrime do
  @moduledoc """
  Grond the Corpsemaker (Prime) - First boss of Prime Kel Voreth.
  Devastating Osun with bone-shattering attacks.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Grond the Corpsemaker (Prime)" do
    boss_id(12101)
    health(9_000_000)
    level(50)
    enrage_timer(360_000)
    interrupt_armor(4)

    phase :one, health_above: 60 do
      phase_emote("GROND SMASH ALL LITTLE ONES!")

      ability :crushing_blow, cooldown: 5_000, target: :tank do
        damage(35000, type: :physical)
        debuff(:armor_break, duration: 10000, stacks: 1)
      end

      ability :ground_pound, cooldown: 10_000 do
        telegraph(:circle, radius: 12, duration: 2000, color: :brown)
        damage(28000, type: :physical)
        movement(:knockback, distance: 8)
      end

      ability :corpse_toss, cooldown: 15_000, target: :farthest do
        telegraph(:circle, radius: 8, duration: 1800, color: :red)
        damage(25000, type: :physical)
        coordination(:spread, damage: 40000, min_distance: 6)
      end
    end

    phase :two, health_between: [30, 60] do
      inherit_phase(:one)
      phase_emote("GROND GETTING ANGRY NOW!")
      enrage_modifier(1.4)

      ability :frenzy, cooldown: 25_000 do
        buff(:frenzied, duration: 12000)
        buff(:damage_increase, duration: 12000)
      end

      ability :bone_storm, cooldown: 22_000 do
        telegraph(:room_wide, duration: 3000)
        damage(35000, type: :physical)
      end

      ability :summon_corpses, cooldown: 30_000 do
        spawn(:add, creature_id: 12111, count: 4, spread: true)
      end
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      phase_emote("GROND CRUSH! GROND KILL! GROND DESTROY!")
      enrage_modifier(1.7)

      ability :apocalyptic_slam, cooldown: 28_000 do
        telegraph(:room_wide, duration: 4000)
        damage(50000, type: :physical)
      end

      ability :bone_eruption, cooldown: 20_000 do
        telegraph(:cross, length: 28, width: 6, duration: 2000, color: :brown)
        damage(42000, type: :physical)
      end
    end

    on_death do
      loot_table(12101)
    end
  end
end
