defmodule BezgelorWorld.Encounter.Bosses.ProtostarAcademy.TrainingConstructAlpha do
  @moduledoc """
  Training Construct Alpha - First boss of Protostar Academy.
  Tutorial boss teaching basic mechanics.
  """

  use BezgelorWorld.Encounter.DSL

  boss "Training Construct Alpha" do
    boss_id 90001
    health 150_000
    level 10
    enrage_timer 180_000
    interrupt_armor 0

    phase :one, health_above: 50 do
      phase_emote "INITIATING TRAINING PROTOCOL. PLEASE DO NOT PANIC."

      ability :training_punch, cooldown: 6_000, target: :tank do
        damage 1500, type: :physical
      end

      ability :tutorial_telegraph, cooldown: 12_000 do
        telegraph :circle, radius: 6, duration: 2500, color: :red
        damage 1200, type: :physical
      end
    end

    phase :two, health_below: 50 do
      inherit_phase :one
      phase_emote "INCREASING DIFFICULTY. STILL NO NEED TO PANIC."
      enrage_modifier 1.2

      ability :advanced_telegraph, cooldown: 15_000 do
        telegraph :cone, angle: 60, length: 15, duration: 2500, color: :red
        damage 1500, type: :physical
      end
    end

    on_death do
      loot_table 90001
    end
  end
end
