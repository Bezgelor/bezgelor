defmodule BezgelorWorld.MythicPlus.Affix do
  @moduledoc """
  Affix behavior definitions for Mythic+ dungeons.

  Affixes modify enemy and dungeon behavior to increase challenge.
  Each affix has specific triggers and effects that must be handled
  during combat.

  ## Affix Categories

  - **Tier 1 (Level 2+)**: General modifiers
    - Fortified: +30% non-boss health, +20% damage
    - Tyrannical: +40% boss health, +15% damage

  - **Tier 2 (Level 4+)**: Add behavior modifiers
    - Bolstering: Killing adds buffs nearby adds
    - Raging: Low health enemies enrage
    - Sanguine: Dead enemies leave healing pools
    - Inspiring: Some enemies buff nearby allies

  - **Tier 3 (Level 7+)**: Environmental/Mechanic
    - Explosive: Spawns explosive orbs
    - Quaking: Periodic AOE around players
    - Grievous: Stacking damage on injured players
    - Volcanic: Fire eruptions at ranged players
    - Necrotic: Tank stacking healing reduction

  - **Seasonal (Level 10+)**: Expansion-specific mechanics
  """

  require Logger

  @type affix_type :: :fortified | :tyrannical | :bolstering | :raging | :sanguine |
                      :inspiring | :explosive | :quaking | :grievous | :volcanic |
                      :necrotic | :seasonal

  @type trigger :: :enemy_death | :low_health | :periodic | :combat_start |
                   :damage_taken | :combat_end

  @callback on_trigger(trigger(), map(), map()) :: {:ok, [map()]} | :noop

  @doc """
  Gets affix definition by ID.
  """
  @spec get_affix(non_neg_integer()) :: map() | nil
  def get_affix(id) do
    affixes()[id]
  end

  @doc """
  Processes affix triggers during combat.
  """
  @spec process_trigger(trigger(), [non_neg_integer()], map()) :: [map()]
  def process_trigger(trigger, affix_ids, context) do
    affix_ids
    |> Enum.flat_map(fn id ->
      case get_affix(id) do
        nil -> []
        affix ->
          case apply_affix(affix, trigger, context) do
            {:ok, effects} -> effects
            :noop -> []
          end
      end
    end)
  end

  @doc """
  Gets stat modifiers for active affixes.
  """
  @spec get_stat_modifiers([non_neg_integer()], atom()) :: map()
  def get_stat_modifiers(affix_ids, entity_type) do
    base = %{health_mult: 1.0, damage_mult: 1.0, speed_mult: 1.0}

    Enum.reduce(affix_ids, base, fn id, acc ->
      case get_affix(id) do
        nil -> acc
        affix -> apply_stat_modifier(affix, entity_type, acc)
      end
    end)
  end

  # Affix Definitions

  defp affixes do
    %{
      # Tier 1
      1 => %{
        id: 1,
        name: "Fortified",
        tier: 1,
        type: :fortified,
        description: "Non-boss enemies have 30% more health and deal 20% more damage",
        triggers: [:combat_start],
        stat_mods: %{
          trash: %{health_mult: 1.3, damage_mult: 1.2},
          boss: %{health_mult: 1.0, damage_mult: 1.0}
        }
      },

      2 => %{
        id: 2,
        name: "Tyrannical",
        tier: 1,
        type: :tyrannical,
        description: "Boss enemies have 40% more health and deal 15% more damage",
        triggers: [:combat_start],
        stat_mods: %{
          trash: %{health_mult: 1.0, damage_mult: 1.0},
          boss: %{health_mult: 1.4, damage_mult: 1.15}
        }
      },

      # Tier 2
      3 => %{
        id: 3,
        name: "Bolstering",
        tier: 2,
        type: :bolstering,
        description: "When any non-boss enemy dies, its death cry buffs nearby allies",
        triggers: [:enemy_death]
      },

      4 => %{
        id: 4,
        name: "Raging",
        tier: 2,
        type: :raging,
        description: "Non-boss enemies enrage at 30% health, dealing 75% increased damage",
        triggers: [:low_health]
      },

      5 => %{
        id: 5,
        name: "Sanguine",
        tier: 2,
        type: :sanguine,
        description: "When slain, non-boss enemies leave behind a pool that heals allies",
        triggers: [:enemy_death]
      },

      6 => %{
        id: 6,
        name: "Inspiring",
        tier: 2,
        type: :inspiring,
        description: "Some non-boss enemies buff nearby allies with immunity to CC",
        triggers: [:combat_start]
      },

      # Tier 3
      7 => %{
        id: 7,
        name: "Explosive",
        tier: 3,
        type: :explosive,
        description: "While in combat, enemies periodically spawn Explosive Orbs",
        triggers: [:periodic]
      },

      8 => %{
        id: 8,
        name: "Quaking",
        tier: 3,
        type: :quaking,
        description: "Players periodically shockwave, dealing damage to nearby allies",
        triggers: [:periodic]
      },

      9 => %{
        id: 9,
        name: "Grievous",
        tier: 3,
        type: :grievous,
        description: "Players below 90% health take stacking damage over time",
        triggers: [:damage_taken]
      },

      10 => %{
        id: 10,
        name: "Volcanic",
        tier: 3,
        type: :volcanic,
        description: "Enemies cause eruptions of flame at distant player locations",
        triggers: [:periodic]
      },

      11 => %{
        id: 11,
        name: "Necrotic",
        tier: 3,
        type: :necrotic,
        description: "Enemy melee attacks apply stacking healing reduction",
        triggers: [:damage_taken]
      },

      # Seasonal
      12 => %{
        id: 12,
        name: "Awakened",
        tier: 4,
        type: :seasonal,
        description: "Lieutenants of an Old God empower dungeons",
        triggers: [:combat_start, :enemy_death]
      }
    }
  end

  # Affix Application

  defp apply_affix(affix, trigger, context) do
    if trigger in (affix[:triggers] || []) do
      apply_affix_effect(affix.type, trigger, context)
    else
      :noop
    end
  end

  defp apply_affix_effect(:bolstering, :enemy_death, context) do
    # Buff nearby enemies when one dies
    nearby_enemies = context[:nearby_enemies] || []

    effects =
      Enum.map(nearby_enemies, fn enemy_id ->
        %{
          type: :buff,
          target: enemy_id,
          buff_id: :bolstering,
          duration: 60_000,
          stacks: 1,
          effects: %{damage_mult: 1.2, health_mult: 1.2}
        }
      end)

    {:ok, effects}
  end

  defp apply_affix_effect(:raging, :low_health, context) do
    enemy_id = context[:enemy_id]
    health_percent = context[:health_percent]

    if health_percent <= 30 do
      {:ok, [%{
        type: :buff,
        target: enemy_id,
        buff_id: :enrage,
        duration: :permanent,
        effects: %{damage_mult: 1.75}
      }]}
    else
      :noop
    end
  end

  defp apply_affix_effect(:sanguine, :enemy_death, context) do
    death_position = context[:position]

    {:ok, [%{
      type: :spawn_hazard,
      hazard_type: :healing_pool,
      position: death_position,
      duration: 20_000,
      radius: 3.0,
      heal_percent: 5  # 5% max HP per second
    }]}
  end

  defp apply_affix_effect(:explosive, :periodic, context) do
    combat_positions = context[:enemy_positions] || []

    # Spawn orb near random enemy
    if length(combat_positions) > 0 do
      pos = Enum.random(combat_positions)

      {:ok, [%{
        type: :spawn_add,
        creature_id: :explosive_orb,
        position: pos,
        health: 1,  # Dies in one hit
        damage_on_expire: 5000  # High damage if not killed
      }]}
    else
      :noop
    end
  end

  defp apply_affix_effect(:quaking, :periodic, context) do
    player_positions = context[:player_positions] || []

    effects =
      Enum.map(player_positions, fn {player_id, pos} ->
        %{
          type: :aoe_damage,
          source: player_id,
          position: pos,
          radius: 8.0,
          damage: 2000,
          damage_type: :nature,
          interrupt: true
        }
      end)

    {:ok, effects}
  end

  defp apply_affix_effect(:grievous, :damage_taken, context) do
    player_id = context[:player_id]
    health_percent = context[:health_percent]

    if health_percent < 90 do
      {:ok, [%{
        type: :dot,
        target: player_id,
        dot_id: :grievous,
        damage_per_tick: 500,
        tick_interval: 2000,
        stacks: true,
        max_stacks: 5
      }]}
    else
      :noop
    end
  end

  defp apply_affix_effect(:volcanic, :periodic, context) do
    ranged_players = context[:ranged_players] || []

    effects =
      Enum.map(ranged_players, fn {player_id, pos} ->
        # Offset the position slightly
        offset_pos = offset_position(pos, 3.0)

        %{
          type: :spawn_hazard,
          hazard_type: :volcanic_plume,
          position: offset_pos,
          delay: 2000,  # 2 second warning
          damage: 3000,
          radius: 2.0
        }
      end)

    {:ok, effects}
  end

  defp apply_affix_effect(:necrotic, :damage_taken, context) do
    if context[:melee_attack] do
      {:ok, [%{
        type: :debuff,
        target: context[:target_id],
        debuff_id: :necrotic_wound,
        duration: 9000,
        stacks: true,
        max_stacks: 50,
        effects: %{healing_reduction: 2}  # 2% per stack
      }]}
    else
      :noop
    end
  end

  defp apply_affix_effect(_type, _trigger, _context), do: :noop

  # Stat Modifiers

  defp apply_stat_modifier(affix, entity_type, acc) do
    entity_key = if entity_type == :boss, do: :boss, else: :trash

    case get_in(affix, [:stat_mods, entity_key]) do
      nil -> acc
      mods ->
        %{acc |
          health_mult: acc.health_mult * (mods[:health_mult] || 1.0),
          damage_mult: acc.damage_mult * (mods[:damage_mult] || 1.0),
          speed_mult: acc.speed_mult * (mods[:speed_mult] || 1.0)
        }
    end
  end

  # Helpers

  defp offset_position({x, y, z}, distance) do
    angle = :rand.uniform() * 2 * :math.pi()
    {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z}
  end
end
