defmodule BezgelorCore.SpellEffect do
  @moduledoc """
  Spell effect definitions and calculations.

  ## Overview

  SpellEffect defines individual effects that spells can apply. A single spell
  may have multiple effects (e.g., damage + debuff). This module also provides
  pure functions for calculating effect values.

  ## Effect Types

  | Type | Description |
  |------|-------------|
  | :damage | Direct damage to target |
  | :heal | Direct healing to target |
  | :dot | Damage over time |
  | :hot | Healing over time |
  | :buff | Beneficial effect on target |
  | :debuff | Harmful effect on target |

  ## Calculation Functions

  All calculation functions are pure - they take input values and return
  results without side effects. This makes them easy to test and reason about.

  ## Usage

      iex> effect = %SpellEffect{type: :damage, amount: 100, scaling: 0.5}
      iex> SpellEffect.calculate(effect, %{power: 200}, %{armor: 0.1})
      {135, false}  # {damage, is_crit}
  """

  @type effect_type :: :damage | :heal | :dot | :hot | :buff | :debuff
  @type scaling_stat :: :power | :tech | :support | nil
  @type damage_school :: :physical | :magic | :tech | nil
  @type buff_type :: :absorb | :stat_boost | :damage_boost | :heal_boost | nil

  defstruct [
    :type,
    amount: 0,
    scaling: 0.0,
    scaling_stat: nil,
    duration: 0,
    tick_interval: 0,
    school: nil,
    buff_type: nil
  ]

  @type t :: %__MODULE__{
          type: effect_type(),
          amount: number(),
          scaling: float(),
          scaling_stat: scaling_stat(),
          duration: non_neg_integer(),
          tick_interval: non_neg_integer(),
          school: damage_school(),
          buff_type: buff_type()
        }

  # Effect type integer codes for packets
  @effect_type_damage 0
  @effect_type_heal 1
  @effect_type_buff 2
  @effect_type_debuff 3
  @effect_type_dot 4
  @effect_type_hot 5

  @doc """
  Calculate the effect value for a given caster and target.

  Returns `{value, is_crit}` tuple.

  ## Parameters

  - `effect` - The SpellEffect struct
  - `caster_stats` - Map with caster stats (power, tech, support, crit_chance)
  - `target_stats` - Map with target stats (armor, magic_resist, etc.)
  - `opts` - Optional keyword list for overrides (e.g., force_crit: true)

  ## Examples

      iex> effect = %SpellEffect{type: :damage, amount: 100, scaling: 0.5, scaling_stat: :power}
      iex> SpellEffect.calculate(effect, %{power: 200, crit_chance: 10}, %{armor: 0.1})
      {135, false}
  """
  @spec calculate(t(), map(), map(), keyword()) :: {integer(), boolean()}
  def calculate(effect, caster_stats, target_stats \\ %{}, opts \\ [])

  def calculate(%__MODULE__{type: :damage} = effect, caster_stats, target_stats, opts) do
    calculate_damage(effect, caster_stats, target_stats, opts)
  end

  def calculate(%__MODULE__{type: :heal} = effect, caster_stats, _target_stats, opts) do
    calculate_healing(effect, caster_stats, opts)
  end

  def calculate(%__MODULE__{type: :dot} = effect, caster_stats, target_stats, opts) do
    # DoT calculates per-tick damage
    calculate_damage(effect, caster_stats, target_stats, opts)
  end

  def calculate(%__MODULE__{type: :hot} = effect, caster_stats, _target_stats, opts) do
    # HoT calculates per-tick healing
    calculate_healing(effect, caster_stats, opts)
  end

  def calculate(%__MODULE__{type: type} = effect, _caster_stats, _target_stats, _opts)
      when type in [:buff, :debuff] do
    # Buffs/debuffs just use base amount
    {effect.amount, false}
  end

  @doc """
  Calculate damage with stat scaling and mitigation.
  """
  @spec calculate_damage(t(), map(), map(), keyword()) :: {integer(), boolean()}
  def calculate_damage(effect, caster_stats, target_stats, opts \\ []) do
    base = effect.amount

    # Apply stat scaling
    stat_bonus = get_stat_bonus(effect, caster_stats)
    scaled = base + stat_bonus

    # Check for critical hit
    crit_chance = Map.get(caster_stats, :crit_chance, 5)
    force_crit = Keyword.get(opts, :force_crit, false)

    {damage, is_crit} =
      if force_crit or roll_crit?(crit_chance) do
        {scaled * crit_multiplier(), true}
      else
        {scaled, false}
      end

    # Apply mitigation based on damage school
    mitigation = get_mitigation(effect.school, target_stats)
    final = damage * (1 - mitigation)

    {max(0, trunc(final)), is_crit}
  end

  @doc """
  Calculate healing with stat scaling.
  """
  @spec calculate_healing(t(), map(), keyword()) :: {integer(), boolean()}
  def calculate_healing(effect, caster_stats, opts \\ []) do
    base = effect.amount

    # Apply stat scaling
    stat_bonus = get_stat_bonus(effect, caster_stats)
    scaled = base + stat_bonus

    # Check for critical heal
    crit_chance = Map.get(caster_stats, :crit_chance, 5)
    force_crit = Keyword.get(opts, :force_crit, false)

    {healing, is_crit} =
      if force_crit or roll_crit?(crit_chance) do
        {scaled * crit_multiplier(), true}
      else
        {scaled, false}
      end

    {max(0, trunc(healing)), is_crit}
  end

  @doc """
  Get the number of ticks for an over-time effect.
  """
  @spec tick_count(t()) :: non_neg_integer()
  def tick_count(%__MODULE__{duration: 0}), do: 0
  def tick_count(%__MODULE__{tick_interval: 0}), do: 0

  def tick_count(%__MODULE__{duration: duration, tick_interval: interval}) do
    div(duration, interval)
  end

  @doc """
  Check if effect is over-time (DoT or HoT).
  """
  @spec over_time?(t()) :: boolean()
  def over_time?(%__MODULE__{type: :dot}), do: true
  def over_time?(%__MODULE__{type: :hot}), do: true
  def over_time?(%__MODULE__{}), do: false

  @doc """
  Check if effect is instant (damage or heal).
  """
  @spec instant?(t()) :: boolean()
  def instant?(%__MODULE__{type: :damage}), do: true
  def instant?(%__MODULE__{type: :heal}), do: true
  def instant?(%__MODULE__{}), do: false

  @doc """
  Convert effect type atom to integer for packet serialization.
  """
  @spec type_to_int(effect_type()) :: non_neg_integer()
  def type_to_int(:damage), do: @effect_type_damage
  def type_to_int(:heal), do: @effect_type_heal
  def type_to_int(:buff), do: @effect_type_buff
  def type_to_int(:debuff), do: @effect_type_debuff
  def type_to_int(:dot), do: @effect_type_dot
  def type_to_int(:hot), do: @effect_type_hot
  def type_to_int(_), do: @effect_type_damage

  @doc """
  Convert integer to effect type atom.
  """
  @spec int_to_type(non_neg_integer()) :: effect_type()
  def int_to_type(@effect_type_damage), do: :damage
  def int_to_type(@effect_type_heal), do: :heal
  def int_to_type(@effect_type_buff), do: :buff
  def int_to_type(@effect_type_debuff), do: :debuff
  def int_to_type(@effect_type_dot), do: :dot
  def int_to_type(@effect_type_hot), do: :hot
  def int_to_type(_), do: :damage

  # Private helpers

  defp get_stat_bonus(%__MODULE__{scaling: scaling}, _caster_stats) when scaling == 0.0, do: 0.0
  defp get_stat_bonus(%__MODULE__{scaling_stat: nil}, _caster_stats), do: 0.0

  defp get_stat_bonus(%__MODULE__{scaling: scaling, scaling_stat: stat}, caster_stats) do
    stat_value = Map.get(caster_stats, stat, 0)
    stat_value * scaling
  end

  defp get_mitigation(nil, _target_stats), do: 0.0
  defp get_mitigation(:physical, target_stats), do: Map.get(target_stats, :armor, 0.0)
  defp get_mitigation(:magic, target_stats), do: Map.get(target_stats, :magic_resist, 0.0)
  defp get_mitigation(:tech, target_stats), do: Map.get(target_stats, :tech_resist, 0.0)
  defp get_mitigation(_, _), do: 0.0

  defp roll_crit?(chance) when is_number(chance) do
    :rand.uniform(100) <= chance
  end

  defp crit_multiplier, do: 1.5
end
