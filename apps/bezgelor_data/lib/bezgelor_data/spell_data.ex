defmodule BezgelorData.SpellData do
  @moduledoc """
  Unified facade for all spell-related data access.

  This module provides a single entry point for fetching spell data,
  hiding the complexity of multiple underlying tables and ID mappings.

  ## Data Relationships

  ```
  spell_id (Spell4.ID)
    ├── Spell4Entry - Base spell definition (cast time, cooldown, targets, etc.)
    │     └── spell4BaseIdBaseSpell -> Spell4Base (tier/level progression data)
    ├── Spell4Effects[] - What the spell does (damage, heal, buff, debuff)
    │     └── Linked via spellId field in Spell4Effects table
    └── Telegraphs[] - Visual targeting shapes (circles, cones, rectangles)
          └── Linked via spell4Id in Spell4Telegraph -> telegraphDamageId
  ```

  ## Usage

      # Get everything for a spell
      {:ok, spell_data} = SpellData.get(43468)
      spell_data.entry      # Raw Spell4 entry map
      spell_data.base       # Raw Spell4Base map (or nil)
      spell_data.effects    # List of Spell4Effects maps
      spell_data.telegraphs # List of TelegraphDamage maps

      # Quick access to just effects (common operation)
      effects = SpellData.effects(43468)

      # Quick access to just telegraphs
      telegraphs = SpellData.telegraphs(43468)

  ## ID Reference

  - `spell_id` - Main spell identifier (Spell4.ID)
  - `base_id` - Spell4Base.ID, linked via entry.spell4BaseIdBaseSpell
  - `effect_id` - Spell4Effects.ID, linked via effect.spellId = spell_id
  - `telegraph_id` - TelegraphDamage.ID, linked via Spell4Telegraph mapping
  """

  alias BezgelorData.Store

  defstruct [
    :id,
    :entry,
    :base,
    :effects,
    :telegraphs
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          entry: map() | nil,
          base: map() | nil,
          effects: [map()],
          telegraphs: [map()]
        }

  # ============================================================================
  # Primary API - Use these functions
  # ============================================================================

  @doc """
  Fetch complete spell data by spell ID.

  Returns a SpellData struct with all related data populated:
  - entry: The raw Spell4 entry (cast time, cooldown, resource cost, etc.)
  - base: The Spell4Base entry if one exists (tier/level data)
  - effects: List of all Spell4Effects for this spell
  - telegraphs: List of all TelegraphDamage shapes for this spell

  ## Example

      {:ok, data} = SpellData.get(43468)
      data.entry.castTime  # Cast time in milliseconds
      length(data.effects) # Number of effects
  """
  @spec get(non_neg_integer()) :: {:ok, t()} | :error
  def get(spell_id) when is_integer(spell_id) do
    case get_entry(spell_id) do
      {:ok, entry} ->
        {:ok,
         %__MODULE__{
           id: spell_id,
           entry: entry,
           base: get_base_for_entry(entry),
           effects: effects(spell_id),
           telegraphs: telegraphs(spell_id)
         }}

      :error ->
        :error
    end
  end

  @doc """
  Fetch complete spell data, raising on not found.
  """
  @spec get!(non_neg_integer()) :: t()
  def get!(spell_id) do
    case get(spell_id) do
      {:ok, data} -> data
      :error -> raise "Spell #{spell_id} not found"
    end
  end

  @doc """
  Get spell effects for a spell ID.

  This is the most common operation - returns the full Spell4Effects maps
  for all effects associated with this spell.

  ## Fields in each effect map

  - effectType: What the effect does (8=damage, 9=heal, 26=triggerSpell, etc.)
  - damageType: Type of damage (0=physical, 1=magic, 2=tech)
  - tickTime: Milliseconds between ticks for DoT/HoT
  - durationTime: Total duration in milliseconds
  - dataBits00-09: Effect-specific parameters
  - threatMultiplier: Threat generation modifier

  ## Example

      effects = SpellData.effects(43468)
      Enum.filter(effects, & &1.effectType == 8) # Get damage effects
  """
  @spec effects(non_neg_integer()) :: [map()]
  def effects(spell_id) when is_integer(spell_id) do
    spell_id
    |> effect_ids()
    |> Enum.map(&get_effect/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get telegraph shapes for a spell ID.

  Returns the full TelegraphDamage maps for all telegraphs associated
  with this spell.

  ## Fields in each telegraph map

  - damageShapeEnum: Shape type (0=Circle, 2=Square, 4=Cone, 5=Pie, 7=Rectangle, 8=LongCone)
  - param00-param05: Shape parameters (radius, angle, dimensions - vary by shape)
  - telegraphTimeStartMs/EndMs: Telegraph timing
  - xPositionOffset/yPositionOffset/zPositionOffset: Position offsets from caster
  - rotationDegrees: Rotation offset

  ## Example

      telegraphs = SpellData.telegraphs(43468)
      Enum.map(telegraphs, & &1.damageShapeEnum) # Get shape types
  """
  @spec telegraphs(non_neg_integer()) :: [map()]
  def telegraphs(spell_id) when is_integer(spell_id) do
    spell_id
    |> telegraph_ids()
    |> Enum.map(&get_telegraph/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Check if a spell exists.
  """
  @spec exists?(non_neg_integer()) :: boolean()
  def exists?(spell_id) when is_integer(spell_id) do
    case get_entry(spell_id) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Check if a spell has any effects.
  """
  @spec has_effects?(non_neg_integer()) :: boolean()
  def has_effects?(spell_id) when is_integer(spell_id) do
    effect_ids(spell_id) != []
  end

  @doc """
  Check if a spell has any telegraphs.
  """
  @spec has_telegraphs?(non_neg_integer()) :: boolean()
  def has_telegraphs?(spell_id) when is_integer(spell_id) do
    telegraph_ids(spell_id) != []
  end

  # ============================================================================
  # ID Accessors - When you need just IDs (rare)
  # ============================================================================

  @doc """
  Get effect IDs for a spell (without fetching full effect data).

  Use `effects/1` instead unless you specifically need just the IDs.
  """
  @spec effect_ids(non_neg_integer()) :: [non_neg_integer()]
  def effect_ids(spell_id) when is_integer(spell_id) do
    case :ets.lookup(index_table(:spell4_effects_by_spell), spell_id) do
      [{^spell_id, ids}] -> ids
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc """
  Get telegraph IDs for a spell (without fetching full telegraph data).

  Use `telegraphs/1` instead unless you specifically need just the IDs.
  """
  @spec telegraph_ids(non_neg_integer()) :: [non_neg_integer()]
  def telegraph_ids(spell_id) when is_integer(spell_id) do
    case :ets.lookup(index_table(:telegraphs_by_spell), spell_id) do
      [{^spell_id, ids}] -> ids
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  # ============================================================================
  # Raw Table Access - For when you have a specific ID
  # ============================================================================

  @doc """
  Get a raw Spell4 entry by ID.
  """
  @spec get_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_entry(spell_id) do
    Store.get(:spell4_entries, spell_id)
  end

  @doc """
  Get a raw Spell4Base entry by ID.
  """
  @spec get_base(non_neg_integer()) :: {:ok, map()} | :error
  def get_base(base_id) do
    Store.get(:spell4_bases, base_id)
  end

  @doc """
  Get a single Spell4Effect by effect ID.

  Returns the effect map or nil if not found.
  """
  @spec get_effect(non_neg_integer()) :: map() | nil
  def get_effect(effect_id) do
    case Store.get(:spell4_effects, effect_id) do
      {:ok, effect} -> effect
      :error -> nil
    end
  end

  @doc """
  Get a single TelegraphDamage by telegraph ID.

  Returns the telegraph map or nil if not found.
  """
  @spec get_telegraph(non_neg_integer()) :: map() | nil
  def get_telegraph(telegraph_id) do
    case Store.get(:telegraph_damage, telegraph_id) do
      {:ok, telegraph} -> telegraph
      :error -> nil
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_base_for_entry(entry) do
    base_id = Map.get(entry, :spell4BaseIdBaseSpell) || Map.get(entry, "spell4BaseIdBaseSpell")

    if base_id && base_id > 0 do
      case get_base(base_id) do
        {:ok, base} -> base
        :error -> nil
      end
    else
      nil
    end
  end

  defp index_table(name) do
    Store.index_table_name(name)
  end
end
