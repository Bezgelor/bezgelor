defmodule BezgelorData.Store.Spells do
  @moduledoc """
  Spell and telegraph-related data queries for the Store.

  Provides functions for querying spell effects, telegraph damage shapes,
  and related spell mechanics data.

  ## Spell Effects

  Spells have effects (Spell4Effects) that define what happens when cast:
  - Damage/heal amounts
  - Effect types (damage, heal, buff, debuff)
  - Duration and tick timing
  - Threat modifiers

  ## Telegraphs

  Telegraphs define the visual and mechanical targeting shapes for spells:
  - Shape type (circle, cone, rectangle, etc.)
  - Dimensions and timing
  - Position offsets from caster
  """

  alias BezgelorData.Store.{Core, Index}

  # Telegraph queries (shape-based spell targeting)

  @doc """
  Get a telegraph damage shape definition by ID.

  Returns the telegraph shape data including:
  - damageShapeEnum: Shape type (0=Circle, 2=Square, 4=Cone, 5=Pie, 7=Rectangle, 8=LongCone)
  - param00-param05: Shape parameters (radius, angle, dimensions vary by shape)
  - telegraphTimeStartMs/EndMs: Telegraph timing
  - xPositionOffset/yPositionOffset/zPositionOffset: Position offsets from caster
  - rotationDegrees: Rotation offset
  """
  @spec get_telegraph_damage(non_neg_integer()) :: {:ok, map()} | :error
  def get_telegraph_damage(telegraph_id) do
    Core.get(:telegraph_damage, telegraph_id)
  end

  @doc """
  Get all telegraph damage IDs associated with a spell.

  Returns a list of telegraph_damage IDs that should be checked for this spell.
  A single spell may have multiple telegraphs (e.g., different phases).
  """
  @spec get_telegraphs_for_spell(non_neg_integer()) :: [non_neg_integer()]
  def get_telegraphs_for_spell(spell_id) do
    Index.lookup_index(:telegraphs_by_spell, spell_id)
  end

  @doc """
  Get all telegraph damage definitions for a spell.

  Returns a list of complete telegraph damage definitions.
  """
  @spec get_telegraph_shapes_for_spell(non_neg_integer()) :: [map()]
  def get_telegraph_shapes_for_spell(spell_id) do
    spell_id
    |> get_telegraphs_for_spell()
  end

  # Spell Effects

  @doc """
  Get a spell effect entry by ID.
  """
  @spec get_spell4_effect(non_neg_integer()) :: {:ok, map()} | :error
  def get_spell4_effect(effect_id) do
    Core.get(:spell4_effects, effect_id)
  end

  @doc """
  Get all spell effect IDs associated with a spell.

  Returns a list of effect IDs that should be applied when this spell is cast.
  A single spell may have multiple effects (damage, buff, debuff, etc.).
  """
  @spec get_spell_effect_ids(non_neg_integer()) :: [non_neg_integer()]
  def get_spell_effect_ids(spell_id) do
    Index.lookup_index(:spell4_effects_by_spell, spell_id)
  end

  @doc """
  Get all spell effect definitions for a spell.

  Returns a list of complete spell effect definitions with all properties:
  - effectType: The type of effect (1=damage, 2=heal, 3=directDamage, etc.)
  - damageType: Type of damage (0=physical, 1=magic, 2=tech)
  - tickTime: Milliseconds between ticks for DoT/HoT effects
  - durationTime: Total duration in milliseconds
  - dataBits00-09: Effect-specific data (damage amounts, etc.)
  - threatMultiplier: Threat generation multiplier
  """
  @spec get_spell_effects(non_neg_integer()) :: [map()]
  def get_spell_effects(spell_id) do
    spell_id
    |> get_spell_effect_ids()
    |> Enum.map(fn id ->
      case get_spell4_effect(id) do
        {:ok, effect} -> effect
        :error -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Check if a spell has any telegraph definitions.
  """
  @spec spell_has_telegraphs?(non_neg_integer()) :: boolean()
  def spell_has_telegraphs?(spell_id) do
    get_telegraphs_for_spell(spell_id) != []
  end
end
