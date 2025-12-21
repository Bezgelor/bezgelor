defmodule BezgelorWorld.Encounter.Bosses.Shiphands.Infestation do
  @moduledoc """
  Infestation shiphand boss.
  Brood Mother with spawning mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Brood Mother" do
    boss_id(60301)
    health(75_000)
    level(18)
    enrage_timer(150_000)
    interrupt_armor(1)

    phase :one, health_above: 40 do
      phase_emote("*chittering noises*")

      ability :venomous_bite, cooldown: 5_000, target: :tank do
        damage(1200, type: :nature)
        debuff(:poisoned, duration: 5000, stacks: 1)
      end

      ability :acid_spit, cooldown: 10_000, target: :random do
        telegraph(:circle, radius: 4, duration: 1500, color: :green)
        damage(1000, type: :nature)
      end

      ability :spawn_broodlings, cooldown: 20_000 do
        spawn(:add, creature_id: 60311, count: 2, spread: true)
      end
    end

    phase :two, health_below: 40 do
      inherit_phase(:one)
      phase_emote("*enraged clicking*")
      enrage_modifier(1.3)

      ability :toxic_cloud, cooldown: 18_000 do
        telegraph(:circle, radius: 8, duration: 2000, color: :green)
        damage(1400, type: :nature)
        debuff(:poisoned, duration: 6000, stacks: 2)
      end

      ability :mass_spawn, cooldown: 25_000 do
        spawn(:add, creature_id: 60311, count: 4, spread: true)
      end
    end

    on_death do
      loot_table(60301)
    end
  end
end
