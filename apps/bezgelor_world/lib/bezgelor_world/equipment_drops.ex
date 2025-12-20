defmodule BezgelorWorld.EquipmentDrops do
  @moduledoc """
  Equipment drop system for creature loot.

  Selects appropriate equipment items from the game's item pool based on:
  - Creature level (determines item level range)
  - Creature tier (determines quality tier)
  - Kill context (group size, special events)

  Equipment items are pre-defined in the Item2 table with stats already
  calculated. This module handles selection, not stat generation.

  ## Quality Tiers

  - 1: Inferior (grey) - vendor trash
  - 2: Average (white) - basic gear
  - 3: Good (green) - standard leveling gear
  - 4: Excellent (blue) - dungeon/challenging content
  - 5: Superb (purple) - raid/elite content
  - 6: Legendary (orange) - rare boss drops
  - 7: Artifact (pink) - extremely rare

  ## Drop Chances by Tier

  - Tier 1 (minion): No equipment drops
  - Tier 2 (standard): 1% green, 0.1% blue
  - Tier 3 (champion): 5% green, 1% blue, 0.1% purple
  - Tier 4 (elite): 10% green, 5% blue, 1% purple
  - Tier 5 (boss): 50% blue, 20% purple, 1% orange
  """

  alias BezgelorData.Store

  require Logger

  # Equipment family IDs
  @armor_family 1
  @weapon_family 2

  # Quality IDs
  @quality_good 3
  @quality_excellent 4
  @quality_superb 5
  @quality_legendary 6

  # Drop chances by tier (creature tier -> quality -> chance%)
  @tier_drop_chances %{
    # Minions don't drop equipment
    1 => %{},
    2 => %{@quality_good => 1, @quality_excellent => 0.1},
    3 => %{@quality_good => 5, @quality_excellent => 1, @quality_superb => 0.1},
    4 => %{@quality_good => 10, @quality_excellent => 5, @quality_superb => 1},
    5 => %{@quality_excellent => 50, @quality_superb => 20, @quality_legendary => 1}
  }

  @doc """
  Roll for equipment drops based on creature parameters.

  ## Parameters

  - `creature_tier` - The creature's tier (1-5, determines quality chances)
  - `creature_level` - The creature's level (determines item level range)
  - `opts` - Options:
    - `:drop_bonus` - Additional drop chance percentage (default 0)
    - `:class_id` - Player class ID for class-specific drops (optional)

  ## Returns

  List of item IDs that dropped, or empty list if no drops.
  """
  @spec roll_equipment(non_neg_integer(), non_neg_integer(), Keyword.t()) :: [non_neg_integer()]
  def roll_equipment(creature_tier, creature_level, opts \\ []) do
    drop_bonus = Keyword.get(opts, :drop_bonus, 0)
    class_id = Keyword.get(opts, :class_id)

    chances = Map.get(@tier_drop_chances, creature_tier, %{})

    # Roll for each quality tier
    Enum.flat_map(chances, fn {quality, base_chance} ->
      adjusted_chance = base_chance + drop_bonus
      roll_for_quality(creature_level, quality, adjusted_chance, class_id)
    end)
  end

  @doc """
  Get a random equipment item for a given level and quality.

  ## Parameters

  - `level` - Target item level (will search +/- 3 levels)
  - `quality` - Quality tier (1-7)
  - `class_id` - Optional class restriction

  ## Returns

  `{:ok, item_id}` or `:error` if no suitable item found.
  """
  @spec get_random_equipment(non_neg_integer(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, non_neg_integer()} | :error
  def get_random_equipment(level, quality, class_id \\ nil) do
    # Get items in level range with matching quality
    level_min = max(1, level - 3)
    level_max = level + 3

    items =
      get_equipment_pool()
      |> Enum.filter(fn item ->
        item_level = item.required_level || 0
        item_quality = item.quality_id || 2

        in_level_range = item_level >= level_min and item_level <= level_max
        matches_quality = item_quality == quality

        matches_class =
          class_id == nil or item.class_required == 0 or item.class_required == class_id

        in_level_range and matches_quality and matches_class
      end)

    case items do
      [] -> :error
      _ -> {:ok, Enum.random(items).id}
    end
  end

  @doc """
  Check if an item ID is equipment (armor or weapon).
  """
  @spec is_equipment?(non_neg_integer()) :: boolean()
  def is_equipment?(item_id) do
    case Store.get(:items, item_id) do
      {:ok, item} ->
        family = item.family_id || 0
        family == @armor_family or family == @weapon_family

      _ ->
        false
    end
  end

  # Private functions

  defp roll_for_quality(level, quality, chance, class_id) do
    roll = :rand.uniform() * 100

    if roll <= chance do
      case get_random_equipment(level, quality, class_id) do
        {:ok, item_id} -> [item_id]
        :error -> []
      end
    else
      []
    end
  end

  defp get_equipment_pool do
    # Get all items from store
    items = Store.list(:items)

    # Filter to equipment families
    Enum.filter(items, fn item ->
      family = item.family_id || 0
      family == @armor_family or family == @weapon_family
    end)
  end
end
