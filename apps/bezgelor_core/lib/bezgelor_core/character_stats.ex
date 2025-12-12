defmodule BezgelorCore.CharacterStats do
  @moduledoc """
  Character combat stat calculations.

  WildStar uses 6 primary attributes that convert to combat stats:
  - Brutality -> Assault Power (DPS)
  - Finesse -> Strikethrough (Hit Rating)
  - Moxie -> Critical Hit Rating
  - Tech -> Support Power (Healing)
  - Insight -> Deflect Critical
  - Grit -> Armor, Max Health

  This module computes effective combat stats from character level,
  class, and any active buff modifiers.
  """

  @type combat_stats :: %{
    power: non_neg_integer(),
    tech: non_neg_integer(),
    support: non_neg_integer(),
    crit_chance: non_neg_integer(),
    armor: float(),
    magic_resist: float(),
    tech_resist: float(),
    max_health: non_neg_integer()
  }

  # Base stat per level (WildStar-authentic scaling)
  @base_stat_per_level 10
  @base_health_per_level 50
  @base_crit_chance 5

  # Class stat multipliers (class_id => {power_mult, tech_mult, support_mult})
  @class_multipliers %{
    1 => {1.2, 0.8, 0.9},   # Warrior - assault focused
    2 => {1.0, 1.0, 1.0},   # Spellslinger - balanced
    3 => {1.1, 0.9, 1.0},   # Stalker - assault/balanced
    4 => {0.8, 1.2, 1.1},   # Esper - support focused
    5 => {0.9, 1.1, 1.1},   # Medic - support focused
    6 => {1.15, 0.85, 0.9}  # Engineer - assault focused
  }

  @doc """
  Compute combat stats from character base attributes.

  ## Parameters

  - `character` - Map with `:level`, `:class`, and optionally `:race`

  ## Returns

  Combat stats map with power, tech, support, crit_chance, armor, etc.
  """
  @spec compute_combat_stats(map()) :: combat_stats()
  def compute_combat_stats(%{level: level, class: class} = _character) do
    {power_mult, tech_mult, support_mult} = Map.get(@class_multipliers, class, {1.0, 1.0, 1.0})

    base_stat = level * @base_stat_per_level

    %{
      power: round(base_stat * power_mult),
      tech: round(base_stat * tech_mult),
      support: round(base_stat * support_mult),
      crit_chance: @base_crit_chance + div(level, 10),
      armor: level * 0.01,
      magic_resist: level * 0.005,
      tech_resist: level * 0.005,
      max_health: 100 + level * @base_health_per_level
    }
  end

  @doc """
  Apply buff modifiers to computed stats.
  """
  @spec apply_buff_modifiers(combat_stats(), map()) :: combat_stats()
  def apply_buff_modifiers(stats, modifiers) do
    %{
      stats |
      power: stats.power + Map.get(modifiers, :power, 0),
      tech: stats.tech + Map.get(modifiers, :tech, 0),
      support: stats.support + Map.get(modifiers, :support, 0),
      crit_chance: stats.crit_chance + Map.get(modifiers, :crit_chance, 0),
      armor: stats.armor + Map.get(modifiers, :armor, 0)
    }
  end
end
