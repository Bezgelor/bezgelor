defmodule BezgelorCore.Spell do
  @moduledoc """
  Spell definition and lookup.

  ## Overview

  This module defines the Spell struct and provides access to spell definitions.
  For Phase 8, spell definitions are hardcoded. Future phases will load from
  static game data tables.

  ## Spell Properties

  | Property | Type | Description |
  |----------|------|-------------|
  | id | integer | Unique spell identifier |
  | name | string | Display name |
  | cast_time | integer | Cast time in milliseconds (0 = instant) |
  | cooldown | integer | Cooldown in milliseconds |
  | gcd | boolean | Triggers global cooldown |
  | range | float | Max range in game units (0 = self) |
  | resource_cost | integer | Resource cost (mana, energy, etc.) |
  | resource_type | atom | Type of resource consumed |
  | target_type | atom | What can be targeted |
  | aoe_radius | float | AoE radius (0 = single target) |
  | effects | list | List of SpellEffect structs |
  | interrupt_flags | list | What can interrupt the cast |
  | spell_school | atom | Damage type for resistances |

  ## Usage

      iex> BezgelorCore.Spell.get(1)
      %BezgelorCore.Spell{id: 1, name: "Fireball", ...}

      iex> BezgelorCore.Spell.instant?(spell)
      false
  """

  @type target_type :: :self | :enemy | :ally | :ground | :aoe
  @type resource_type :: :mana | :energy | :focus | :none
  @type spell_school :: :physical | :magic | :tech
  @type interrupt_flag :: :damage | :movement | :stun | :silence

  defstruct [
    :id,
    :name,
    :description,
    cast_time: 0,
    cooldown: 0,
    gcd: true,
    range: 0.0,
    resource_cost: 0,
    resource_type: :none,
    target_type: :self,
    aoe_radius: 0.0,
    effects: [],
    interrupt_flags: [:damage, :stun, :silence],
    spell_school: :magic,
    hostile: false
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          description: String.t() | nil,
          cast_time: non_neg_integer(),
          cooldown: non_neg_integer(),
          gcd: boolean(),
          range: float(),
          resource_cost: non_neg_integer(),
          resource_type: resource_type(),
          target_type: target_type(),
          aoe_radius: float(),
          effects: list(),
          interrupt_flags: [interrupt_flag()],
          spell_school: spell_school(),
          hostile: boolean()
        }

  # Test spells for Phase 8 (built at runtime to avoid compile-time issues)
  defp build_spells do
    alias BezgelorCore.SpellEffect

    %{
      1 => %__MODULE__{
        id: 1,
        name: "Fireball",
        description: "Hurls a ball of fire at the target, dealing magic damage.",
        cast_time: 2000,
        cooldown: 5000,
        gcd: true,
        range: 30.0,
        resource_cost: 20,
        resource_type: :mana,
        target_type: :enemy,
        effects: [
          %SpellEffect{
            type: :damage,
            amount: 100,
            scaling: 0.5,
            scaling_stat: :power,
            school: :magic
          }
        ],
        spell_school: :magic,
        hostile: true
      },
      2 => %__MODULE__{
        id: 2,
        name: "Heal",
        description: "Heals a friendly target.",
        cast_time: 1500,
        cooldown: 0,
        gcd: true,
        range: 30.0,
        resource_cost: 25,
        resource_type: :mana,
        target_type: :ally,
        effects: [
          %SpellEffect{
            type: :heal,
            amount: 150,
            scaling: 0.8,
            scaling_stat: :support
          }
        ],
        spell_school: :magic
      },
      3 => %__MODULE__{
        id: 3,
        name: "Quick Strike",
        description: "A fast melee attack.",
        cast_time: 0,
        cooldown: 3000,
        gcd: true,
        range: 5.0,
        resource_cost: 10,
        resource_type: :energy,
        target_type: :enemy,
        effects: [
          %SpellEffect{
            type: :damage,
            amount: 50,
            scaling: 0.3,
            scaling_stat: :power,
            school: :physical
          }
        ],
        interrupt_flags: [],
        spell_school: :physical
      },
      4 => %__MODULE__{
        id: 4,
        name: "Shield",
        description: "Surrounds yourself with a protective barrier.",
        cast_time: 0,
        cooldown: 30_000,
        gcd: true,
        range: 0.0,
        resource_cost: 30,
        resource_type: :mana,
        target_type: :self,
        effects: [
          %SpellEffect{
            type: :buff,
            amount: 100,
            duration: 10_000,
            buff_type: :absorb
          }
        ],
        spell_school: :magic
      },
      5 => %__MODULE__{
        id: 5,
        name: "Regeneration",
        description: "Heals yourself over time.",
        cast_time: 2000,
        cooldown: 10_000,
        gcd: true,
        range: 0.0,
        resource_cost: 35,
        resource_type: :mana,
        target_type: :self,
        effects: [
          %SpellEffect{
            type: :hot,
            amount: 25,
            duration: 10_000,
            tick_interval: 1000,
            scaling: 0.2,
            scaling_stat: :support
          }
        ],
        spell_school: :magic
      }
    }
  end

  @doc """
  Get a spell by ID.

  ## Examples

      iex> BezgelorCore.Spell.get(1)
      %BezgelorCore.Spell{id: 1, name: "Fireball", ...}

      iex> BezgelorCore.Spell.get(999)
      nil
  """
  @spec get(non_neg_integer()) :: t() | nil
  def get(id) when is_integer(id) do
    Map.get(build_spells(), id)
  end

  @doc """
  Check if a spell exists.
  """
  @spec exists?(non_neg_integer()) :: boolean()
  def exists?(id) when is_integer(id) do
    Map.has_key?(build_spells(), id)
  end

  @doc """
  Check if a spell is instant cast.
  """
  @spec instant?(t()) :: boolean()
  def instant?(%__MODULE__{cast_time: 0}), do: true
  def instant?(%__MODULE__{}), do: false

  @doc """
  Check if a spell requires a target.
  """
  @spec requires_target?(t()) :: boolean()
  def requires_target?(%__MODULE__{target_type: :self}), do: false
  def requires_target?(%__MODULE__{}), do: true

  @doc """
  Check if a spell can target enemies.
  """
  @spec targets_enemy?(t()) :: boolean()
  def targets_enemy?(%__MODULE__{target_type: :enemy}), do: true
  def targets_enemy?(%__MODULE__{}), do: false

  @doc """
  Check if a spell can target allies.
  """
  @spec targets_ally?(t()) :: boolean()
  def targets_ally?(%__MODULE__{target_type: :ally}), do: true
  def targets_ally?(%__MODULE__{}), do: false

  @doc """
  Check if a spell is AoE.
  """
  @spec aoe?(t()) :: boolean()
  def aoe?(%__MODULE__{target_type: :aoe}), do: true
  def aoe?(%__MODULE__{target_type: :ground}), do: true
  def aoe?(%__MODULE__{aoe_radius: radius}) when radius > 0, do: true
  def aoe?(%__MODULE__{}), do: false

  @doc """
  Get all available spell IDs.
  """
  @spec all_ids() :: [non_neg_integer()]
  def all_ids, do: Map.keys(build_spells())

  @doc """
  Get all spells.
  """
  @spec all() :: [t()]
  def all, do: Map.values(build_spells())

  @doc """
  Global cooldown duration in milliseconds.
  """
  @spec global_cooldown() :: non_neg_integer()
  def global_cooldown, do: 1000
end
