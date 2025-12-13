defmodule BezgelorWorld.Encounter.Bosses.ProtostarAcademy.ChiefInstructorMaximillion do
  @moduledoc """
  Chief Instructor Maximillion - Final boss of Protostar Academy.
  Comprehensive tutorial boss with all basic mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Chief Instructor Maximillion" do
    boss_id 90003
    health 300_000
    level 15
    enrage_timer 300_000
    interrupt_armor 1

    phase :one, health_above: 70 do
      phase_emote "Attention students! Today's final exam begins NOW!"

      ability :instructor_strike, cooldown: 5_000, target: :tank do
        damage 2500, type: :physical
      end

      ability :pop_quiz, cooldown: 12_000, target: :random do
        telegraph :circle, radius: 6, duration: 2000, color: :red
        damage 2200, type: :physical
      end

      ability :lesson_beam, cooldown: 15_000 do
        telegraph :line, width: 4, length: 22, duration: 2000, color: :blue
        damage 2800, type: :magic
      end
    end

    phase :two, health_between: [40, 70] do
      inherit_phase :one
      phase_emote "Mid-term examination! Show me what you've learned!"
      enrage_modifier 1.2

      ability :call_teaching_assistants, cooldown: 25_000 do
        spawn :add, creature_id: 90031, count: 2, spread: true
      end

      ability :surprise_test, cooldown: 18_000 do
        telegraph :cone, angle: 90, length: 18, duration: 2000, color: :red
        damage 3000, type: :physical
      end
    end

    phase :three, health_below: 40 do
      inherit_phase :two
      phase_emote "FINAL EXAMINATION! This determines your grade!"
      enrage_modifier 1.35

      ability :graduation_ceremony, cooldown: 25_000 do
        telegraph :room_wide, duration: 3000
        damage 4000, type: :magic
      end

      ability :dean_summons, cooldown: 22_000 do
        spawn :add, creature_id: 90032, count: 3, spread: true
      end

      ability :expulsion_beam, cooldown: 18_000 do
        telegraph :cross, length: 20, width: 4, duration: 2000, color: :red
        damage 3500, type: :magic
      end
    end

    on_death do
      loot_table 90003
      achievement 9000  # Protostar Academy Graduate
    end
  end
end
