defmodule BezgelorWorld.Encounter.Bosses.StormtalonsLair.Stormtalon do
  @moduledoc """
  Stormtalon encounter - Stormtalon's Lair

  Data sources: client_data
  Data completeness: 30%
  Generated: 2025-12-13

  Known abilities from client data:
  - Static Wave: spell_base_ids [13106, 23994, 24239]
  - Lightning Storm: spell_base_ids [14432, 24058]
  - Thunder Cross: spell_base_ids [23168]
  - Electrostatic Pulse: spell_base_ids [23423, 31148]
  - Manifest Cyclone: spell_base_ids [24209]
  """

  use BezgelorWorld.Encounter.DSL

  boss "Stormtalon" do
    boss_id(17163)
    health(400_000)
    level(20)
    enrage_timer(480_000)
    interrupt_armor(2)

    # TODO: Add phases and abilities based on research
    # Use the LLM scripting guide: docs/llm-scripting-guide.md

    phase :one, health_above: 70 do
      phase_emote("Stormtalon engages!")

      # TODO: Add abilities
      ability :basic_attack, cooldown: 10_000, target: :tank do
        telegraph(:circle, radius: 5, duration: 2000, color: :red)
        damage(3000, type: :physical)
      end
    end

    phase :two, health_between: {30, 70} do
      inherit_phase(:one)

      # TODO: Add phase two abilities
    end

    phase :three, health_below: 30 do
      inherit_phase(:two)
      enrage_modifier(1.5)

      # TODO: Add enrage abilities
    end

    on_death do
      loot_table(17163)
    end
  end
end
