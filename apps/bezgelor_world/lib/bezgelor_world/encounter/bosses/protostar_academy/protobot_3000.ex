defmodule BezgelorWorld.Encounter.Bosses.ProtostarAcademy.Protobot3000 do
  @moduledoc """
  Protobot 3000 - Second boss of Protostar Academy.
  Teaches interrupt and add mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Protobot 3000" do
    boss_id(90002)
    health(200_000)
    level(12)
    enrage_timer(180_000)
    interrupt_armor(1)

    phase :one, health_above: 50 do
      phase_emote("PROTOBOT 3000 ONLINE. TEACHING MODULE: INTERRUPTS.")

      ability :plasma_bolt, cooldown: 5_000, target: :tank do
        damage(2000, type: :magic)
      end

      ability :overcharge_beam, cooldown: 15_000 do
        telegraph(:line, width: 4, length: 20, duration: 2000, color: :blue)
        damage(2500, type: :magic)
      end

      ability :deploy_training_bots, cooldown: 25_000 do
        spawn(:add, creature_id: 90012, count: 2, spread: true)
      end
    end

    phase :two, health_below: 50 do
      inherit_phase(:one)
      phase_emote("ADVANCED LESSON: ADDS AND PRIORITY.")
      enrage_modifier(1.25)

      ability :mass_deployment, cooldown: 22_000 do
        spawn(:add, creature_id: 90013, count: 3, spread: true)
      end

      ability :system_shock, cooldown: 18_000 do
        telegraph(:circle, radius: 10, duration: 2500, color: :blue)
        damage(3000, type: :magic)
      end
    end

    on_death do
      loot_table(90002)
    end
  end
end
