defmodule BezgelorWorld.Loot do
  @moduledoc """
  Data-driven loot table system with level scaling and modifiers.

  ## Architecture

  Loot tables are loaded from JSON data files and resolved per-creature using:
  1. Direct creature overrides (specific creatures can have custom tables)
  2. Rule-based resolution (race, tier, difficulty determine base table)

  ## Loot Entry Structure

  - `item_id` - The item template ID (0 = gold/currency)
  - `chance` - Drop chance (1-100)
  - `min` - Minimum quantity
  - `max` - Maximum quantity
  - `type` - "gold" or "item"

  ## Modifiers

  - `gold_multiplier` - Multiplies gold drops (from tier/difficulty)
  - `drop_bonus` - Added to drop chance percentage
  - `level_scaling` - Adjusts drops based on level difference

  ## Usage

      # Roll loot for a creature (preferred - pass all context)
      drops = Loot.roll_creature_loot(creature_id, creature_level, killer_level, opts)

      # Roll from a specific table
      drops = Loot.roll_table(table_id, opts)
  """

  alias BezgelorData.Store
  alias BezgelorWorld.EquipmentDrops

  require Logger

  @type loot_entry :: %{
          item_id: non_neg_integer(),
          chance: number(),
          min: pos_integer(),
          max: pos_integer(),
          type: String.t()
        }

  @type drop :: {item_id :: non_neg_integer(), quantity :: non_neg_integer()}

  @type roll_options :: [
          group_size: pos_integer(),
          bonus_chance: number(),
          no_gold: boolean(),
          gold_multiplier: number(),
          drop_bonus: number(),
          creature_tier: pos_integer(),
          class_id: non_neg_integer()
        ]

  @doc """
  Roll loot for a creature based on data-driven tables.

  ## Parameters

  - `creature_id` - The creature template ID
  - `creature_level` - The creature's level (for scaling calculations)
  - `killer_level` - The killer's level (for scaling calculations)
  - `opts` - Additional options

  ## Options

  - `:group_size` - Number of players in group (increases drop chance)
  - `:bonus_chance` - Additional drop chance percentage
  - `:no_gold` - If true, skips gold drops
  - `:creature_tier` - Creature tier for equipment drop chances (1-5)
  - `:class_id` - Player class ID for class-specific equipment

  ## Returns

  List of `{item_id, quantity}` tuples. Item ID 0 represents gold.
  """
  @spec roll_creature_loot(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          roll_options()
        ) ::
          [drop()]
  def roll_creature_loot(creature_id, creature_level, killer_level, opts \\ []) do
    # Resolve loot table and modifiers for this creature
    # Store.resolve_creature_loot always returns {:ok, ...} with fallback to defaults
    {:ok, resolution} = Store.resolve_creature_loot(creature_id)

    loot_table_id = resolution.loot_table_id
    base_gold_multiplier = resolution.gold_multiplier
    base_drop_bonus = resolution.drop_bonus
    extra_table = Map.get(resolution, :extra_table)

    # Calculate level scaling modifier
    level_modifier = calculate_level_modifier(killer_level, creature_level)

    # Calculate group bonus
    group_size = Keyword.get(opts, :group_size, 1)
    group_bonus = calculate_group_bonus(group_size)

    # Build options with all modifiers combined
    roll_opts =
      opts
      |> Keyword.put(:gold_multiplier, base_gold_multiplier * level_modifier.gold_scale)
      |> Keyword.put(:drop_bonus, base_drop_bonus + level_modifier.drop_bonus + group_bonus)

    # Roll main loot table
    main_drops = roll_table(loot_table_id, roll_opts)

    # Roll extra table if present (elite bonus loot)
    extra_drops =
      if extra_table do
        roll_table(extra_table, roll_opts)
      else
        []
      end

    # Roll for equipment drops based on creature tier
    creature_tier = Keyword.get(opts, :creature_tier, 1)
    class_id = Keyword.get(opts, :class_id)
    drop_bonus = base_drop_bonus + level_modifier.drop_bonus + group_bonus

    equipment_drops =
      creature_tier
      |> EquipmentDrops.roll_equipment(creature_level, drop_bonus: drop_bonus, class_id: class_id)
      |> Enum.map(fn item_id -> {item_id, 1} end)

    main_drops ++ extra_drops ++ equipment_drops
  end

  @doc """
  Roll loot from a specific loot table ID.

  ## Options

  - `:gold_multiplier` - Multiplier for gold amounts (default 1.0)
  - `:drop_bonus` - Bonus to add to drop chances (default 0)
  - `:group_size` - Group size for bonus calculations (applied if not already in drop_bonus)
  - `:no_gold` - Skip gold drops
  """
  @spec roll_table(non_neg_integer(), Keyword.t()) :: [drop()]
  def roll_table(table_id, opts \\ []) do
    case Store.get_loot_table(table_id) do
      {:ok, table} ->
        entries = Map.get(table, :entries, [])
        roll_entries(entries, opts)

      :error ->
        Logger.debug("Loot table #{table_id} not found")
        []
    end
  end

  @doc """
  Roll loot directly from a list of entries.

  Useful for custom loot scenarios (quest rewards, event loot, etc.)
  """
  @spec roll_entries([loot_entry()], Keyword.t()) :: [drop()]
  def roll_entries(entries, opts \\ []) do
    gold_multiplier = Keyword.get(opts, :gold_multiplier, 1.0)
    drop_bonus = Keyword.get(opts, :drop_bonus, 0)
    no_gold = Keyword.get(opts, :no_gold, false)

    entries
    |> maybe_filter_gold(no_gold)
    |> Enum.filter(fn entry -> roll_chance?(entry, drop_bonus) end)
    |> Enum.map(fn entry -> roll_quantity(entry, gold_multiplier) end)
  end

  @doc """
  Get total gold value from loot drops.

  Gold is represented by item_id 0.
  """
  @spec gold_from_drops([drop()]) :: non_neg_integer()
  def gold_from_drops(drops) do
    drops
    |> Enum.filter(fn {item_id, _} -> item_id == 0 end)
    |> Enum.reduce(0, fn {_, amount}, acc -> acc + amount end)
  end

  @doc """
  Get non-gold items from loot drops.
  """
  @spec items_from_drops([drop()]) :: [drop()]
  def items_from_drops(drops) do
    Enum.reject(drops, fn {item_id, _} -> item_id == 0 end)
  end

  @doc """
  Check if drops contain any items (non-gold).
  """
  @spec has_items?([drop()]) :: boolean()
  def has_items?(drops), do: items_from_drops(drops) != []

  @doc """
  Check if drops contain gold.
  """
  @spec has_gold?([drop()]) :: boolean()
  def has_gold?(drops), do: gold_from_drops(drops) > 0

  @doc """
  Calculate group loot bonus based on group size.

  Larger groups get slightly increased drop chances.
  """
  @spec calculate_group_bonus(pos_integer()) :: number()
  def calculate_group_bonus(group_size) when group_size <= 1, do: 0
  def calculate_group_bonus(group_size) when group_size <= 5, do: (group_size - 1) * 2
  def calculate_group_bonus(group_size) when group_size <= 20, do: 8 + (group_size - 5)
  def calculate_group_bonus(_group_size), do: 23

  # Private functions

  defp roll_chance?(entry, bonus) do
    base_chance = get_entry_value(entry, :chance, 0)
    effective_chance = min(base_chance + bonus, 100)
    :rand.uniform(100) <= effective_chance
  end

  defp roll_quantity(entry, gold_multiplier) do
    item_id = get_entry_value(entry, :item_id, 0)
    min_qty = get_entry_value(entry, :min, 1)
    max_qty = get_entry_value(entry, :max, 1)
    entry_type = get_entry_value(entry, :type, "item")

    base_quantity =
      if min_qty == max_qty do
        min_qty
      else
        Enum.random(min_qty..max_qty)
      end

    # Apply gold multiplier for gold drops
    quantity =
      if item_id == 0 or entry_type == "gold" do
        round(base_quantity * gold_multiplier)
      else
        base_quantity
      end

    {item_id, max(quantity, 1)}
  end

  # Flexible entry value getter that handles both atom and string keys
  defp get_entry_value(entry, key, default) when is_atom(key) do
    case Map.get(entry, key) do
      nil -> Map.get(entry, Atom.to_string(key), default)
      value -> value
    end
  end

  defp maybe_filter_gold(entries, false), do: entries

  defp maybe_filter_gold(entries, true) do
    Enum.reject(entries, fn entry ->
      get_entry_value(entry, :item_id, 0) == 0 or get_entry_value(entry, :type, "item") == "gold"
    end)
  end

  defp calculate_level_modifier(killer_level, creature_level) do
    level_diff = killer_level - creature_level

    cond do
      # Much lower level creature - reduced rewards
      level_diff > 10 ->
        %{gold_scale: 0.25, drop_bonus: -20}

      level_diff > 5 ->
        %{gold_scale: 0.5, drop_bonus: -10}

      level_diff > 2 ->
        %{gold_scale: 0.75, drop_bonus: -5}

      # Normal range
      level_diff >= -2 ->
        %{gold_scale: 1.0, drop_bonus: 0}

      # Higher level creature - bonus rewards
      level_diff >= -5 ->
        %{gold_scale: 1.25, drop_bonus: 5}

      level_diff >= -10 ->
        %{gold_scale: 1.5, drop_bonus: 10}

      # Much higher level - big bonus
      true ->
        %{gold_scale: 2.0, drop_bonus: 15}
    end
  end
end
