defmodule BezgelorCore.BuffDebuff do
  @moduledoc """
  Buff and debuff definitions.

  ## Overview

  Buffs are beneficial effects applied to entities (players, creatures).
  Debuffs are harmful effects. Both have a duration and can modify stats
  or provide special effects like damage absorption.

  ## Buff Types

  | Type | Description |
  |------|-------------|
  | :absorb | Absorbs incoming damage |
  | :stat_modifier | Modifies a stat (power, armor, etc.) |
  | :damage_boost | Increases outgoing damage |
  | :heal_boost | Increases healing done |
  | :periodic | Periodic effect (DoT/HoT tick tracking) |

  ## Usage

      iex> buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      iex> BuffDebuff.buff?(buff)
      true
  """

  @type buff_type :: :absorb | :stat_modifier | :damage_boost | :heal_boost | :periodic
  @type stat :: :power | :tech | :support | :armor | :magic_resist | :tech_resist | :crit_chance | nil

  defstruct [
    :id,
    :spell_id,
    :buff_type,
    :stat,
    amount: 0,
    duration: 0,
    is_debuff: false,
    stacks: 1,
    max_stacks: 1
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          spell_id: non_neg_integer(),
          buff_type: buff_type(),
          stat: stat(),
          amount: integer(),
          duration: non_neg_integer(),
          is_debuff: boolean(),
          stacks: non_neg_integer(),
          max_stacks: non_neg_integer()
        }

  # Buff type integer codes for packets
  @type_absorb 0
  @type_stat_modifier 1
  @type_damage_boost 2
  @type_heal_boost 3
  @type_periodic 4

  @doc """
  Create a new buff/debuff from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      spell_id: Map.fetch!(attrs, :spell_id),
      buff_type: Map.fetch!(attrs, :buff_type),
      stat: Map.get(attrs, :stat),
      amount: Map.fetch!(attrs, :amount),
      duration: Map.fetch!(attrs, :duration),
      is_debuff: Map.get(attrs, :is_debuff, false),
      stacks: Map.get(attrs, :stacks, 1),
      max_stacks: Map.get(attrs, :max_stacks, 1)
    }
  end

  @doc """
  Check if this is a buff (not a debuff).
  """
  @spec buff?(t()) :: boolean()
  def buff?(%__MODULE__{is_debuff: false}), do: true
  def buff?(%__MODULE__{}), do: false

  @doc """
  Check if this is a debuff.
  """
  @spec debuff?(t()) :: boolean()
  def debuff?(%__MODULE__{is_debuff: true}), do: true
  def debuff?(%__MODULE__{}), do: false

  @doc """
  Check if this buff modifies a stat.
  """
  @spec stat_modifier?(t()) :: boolean()
  def stat_modifier?(%__MODULE__{buff_type: :stat_modifier}), do: true
  def stat_modifier?(%__MODULE__{}), do: false

  @doc """
  Convert buff type atom to integer for packet serialization.
  """
  @spec type_to_int(buff_type()) :: non_neg_integer()
  def type_to_int(:absorb), do: @type_absorb
  def type_to_int(:stat_modifier), do: @type_stat_modifier
  def type_to_int(:damage_boost), do: @type_damage_boost
  def type_to_int(:heal_boost), do: @type_heal_boost
  def type_to_int(:periodic), do: @type_periodic
  def type_to_int(_), do: @type_absorb

  @doc """
  Convert integer to buff type atom.
  """
  @spec int_to_type(non_neg_integer()) :: buff_type()
  def int_to_type(@type_absorb), do: :absorb
  def int_to_type(@type_stat_modifier), do: :stat_modifier
  def int_to_type(@type_damage_boost), do: :damage_boost
  def int_to_type(@type_heal_boost), do: :heal_boost
  def int_to_type(@type_periodic), do: :periodic
  def int_to_type(_), do: :absorb
end
