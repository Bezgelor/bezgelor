defmodule BezgelorWorld.Encounter.Bosses.VeteranKelVoreth.SlavemasterDrokkVeteran do
  @moduledoc """
  Slavemaster Drokk (Veteran) encounter - Veteran Kel Voreth (Second Boss)

  The veteran version of Drokk with enhanced slave mechanics. Features:
  - 3-phase fight with Shock Chain spread
  - Shackle crowd control debuff
  - Mass slave spawns in final phase

  ## Strategy
  Phase 1 (100-65%): Spread for Shock Chain, kill slaves quickly
  Phase 2 (65-35%): Avoid Charged Whip cross, dispel Shackle
  Phase 3 (<35%): Handle Slave Uprising waves, burn before Execute

  Data sources: instance_bosses.json
  Generated: 2025-12-13, Enhanced: 2025-12-13
  """

  use BezgelorWorld.Encounter.DSL

  boss "Slavemaster Drokk (Veteran)" do
    boss_id(50602)
    health(4_200_000)
    level(50)
    enrage_timer(540_000)
    interrupt_armor(4)

    phase :one, health_above: 65 do
      phase_emote("You will serve or you will DIE!")

      ability :slave_driver, cooldown: 10_000, target: :tank do
        damage(22000, type: :physical)
        debuff(:driven, duration: 10000, stacks: 1)
      end

      ability :shock_chain, cooldown: 18_000, target: :random do
        telegraph(:circle, radius: 5, duration: 3000, color: :blue)
        coordination(:spread, min_distance: 8, damage: 16000)
      end

      ability :whip_crack, cooldown: 12_000 do
        telegraph(:line, width: 5, length: 30, duration: 2000, color: :red)
        damage(14000, type: :physical)
      end

      ability :summon_slaves, cooldown: 25_000 do
        spawn(:add, creature_id: 50622, count: 3, spread: true)
      end

      ability :intimidate, cooldown: 20_000 do
        telegraph(:cone, angle: 60, length: 20, duration: 1800, color: :red)
        damage(12000, type: :physical)
        debuff(:intimidated, duration: 6000)
      end
    end

    phase :two, health_between: {35, 65} do
      inherit_phase(:one)
      phase_emote("Work harder, slaves!")
      enrage_modifier(1.3)

      ability :mass_punishment, cooldown: 28_000 do
        telegraph(:room_wide, duration: 3500)
        damage(12000, type: :physical)
        debuff(:punished, duration: 10000, stacks: 1)
      end

      ability :shackle, cooldown: 20_000, target: :random do
        telegraph(:circle, radius: 4, duration: 1500, color: :gray)
        debuff(:shackled, duration: 6000)
      end

      ability :charged_whip, cooldown: 22_000 do
        telegraph(:cross, length: 30, width: 5, duration: 2500, color: :blue)
        damage(16000, type: :magic)
      end

      ability :slave_push, cooldown: 25_000 do
        telegraph(:cone, angle: 120, length: 25, duration: 2000, color: :red)
        damage(14000, type: :physical)
        movement(:knockback, distance: 10)
      end

      ability :reinforcements, cooldown: 32_000 do
        spawn(:add, creature_id: 50622, count: 2, spread: true)
        spawn(:add, creature_id: 50623, count: 1, spread: true)
      end
    end

    phase :three, health_below: 35 do
      inherit_phase(:two)
      phase_emote("NO ONE ESCAPES THE SLAVEMASTER!")
      enrage_modifier(1.6)

      ability :final_punishment, cooldown: 30_000 do
        telegraph(:room_wide, duration: 4500)
        damage(18000, type: :physical)
        debuff(:final_punishment, duration: 15000, stacks: 2)
      end

      ability :slave_uprising, cooldown: 35_000 do
        spawn(:wave, waves: 2, delay: 4000, creature_id: 50622, count_per_wave: 4)
      end

      ability :execute, cooldown: 25_000 do
        telegraph(:circle, radius: 15, duration: 3000, color: :red)
        damage(22000, type: :physical)
      end

      ability :chains_of_domination, cooldown: 28_000, target: :random do
        telegraph(:line, width: 6, length: 35, duration: 2000, color: :gray)
        damage(16000, type: :physical)
        debuff(:dominated, duration: 8000)
      end

      ability :final_command, cooldown: 45_000 do
        buff(:commanding, duration: 15000)
        buff(:damage_increase, duration: 15000)
        spawn(:add, creature_id: 50622, count: 3, spread: true)
      end
    end

    on_death do
      loot_table(50602)
    end
  end
end
