defmodule BezgelorData.Store.Creatures do
  @moduledoc """
  Creature-related data queries for the Store.

  Provides functions for querying creature loot rules, loot resolution,
  and harvest node loot data.

  ## Loot Resolution

  Creature loot is resolved using a rule-based system:
  1. First check for direct override by creature_id
  2. If no override, use race/tier/difficulty mappings from rules

  ## Harvest Loot

  Harvest nodes (mining, farming, etc.) have their own loot tables
  indexed by creature_id (the node's creature template).
  """

  alias BezgelorData.Store.Core

  @doc """
  Get creature loot rules configuration.

  Returns the full rules map containing race mappings, tier modifiers,
  and difficulty modifiers used for loot resolution.
  """
  @spec get_creature_loot_rules() :: map() | nil
  def get_creature_loot_rules do
    case :ets.lookup(Core.table_name(:creature_loot_rules), :rules) do
      [{:rules, rules}] -> rules
      [] -> nil
    end
  end

  @doc """
  Get loot table override for a specific creature.

  Overrides take precedence over rule-based resolution.
  """
  @spec get_creature_loot_override(non_neg_integer()) :: map() | nil
  def get_creature_loot_override(creature_id) do
    case :ets.lookup(Core.table_name(:creature_loot_rules), {:override, creature_id}) do
      [{{:override, ^creature_id}, override}] ->
        override

      _ ->
        # Try alternate key format
        case :ets.match(Core.table_name(:creature_loot_rules), {:override, creature_id, :"$1"}) do
          [[override]] -> override
          _ -> nil
        end
    end
  end

  @doc """
  Get loot category tables mapping.

  Maps loot categories to their respective loot table IDs.
  """
  @spec get_loot_category_tables() :: map() | nil
  def get_loot_category_tables do
    case :ets.lookup(Core.table_name(:creature_loot_rules), :categories) do
      [{:categories, categories}] -> categories
      [] -> nil
    end
  end

  @doc """
  Resolve loot configuration for a creature.

  Checks for direct override first, then falls back to rule-based resolution
  using the creature's race, tier, and difficulty.

  Returns {:ok, %{loot_table_id, gold_multiplier, drop_bonus}} or :error
  """
  @spec resolve_creature_loot(non_neg_integer()) :: {:ok, map()} | :error
  def resolve_creature_loot(creature_id) do
    case get_creature_loot_override(creature_id) do
      nil ->
        resolve_loot_by_rules(creature_id)

      override ->
        {:ok,
         %{
           loot_table_id: override.loot_table_id,
           gold_multiplier: Map.get(override, :gold_multiplier, 1.0),
           drop_bonus: Map.get(override, :drop_bonus, 0)
         }}
    end
  end

  @doc """
  Get harvest node loot data by creature ID.

  Returns loot configuration for a harvest node including:
  - tradeskill_id: The gathering profession (13=Mining, 15=Survivalist, 18=Relic Hunter, 20=Farming)
  - tradeskill_name: Human-readable profession name
  - tier: Skill tier (1-5)
  - loot: Map with :primary and :secondary drop lists
  """
  @spec get_harvest_loot(non_neg_integer()) :: {:ok, map()} | :error
  def get_harvest_loot(creature_id), do: Core.get(:harvest_loot, creature_id)

  @doc """
  Get all harvest loot mappings.
  """
  @spec get_all_harvest_loot() :: [map()]
  def get_all_harvest_loot, do: Core.list(:harvest_loot)

  @doc """
  Get harvest loot by tradeskill ID.
  """
  @spec get_harvest_loot_by_tradeskill(non_neg_integer()) :: [map()]
  def get_harvest_loot_by_tradeskill(tradeskill_id) do
    Core.list(:harvest_loot)
    |> Enum.filter(fn data ->
      Map.get(data, :tradeskill_id) == tradeskill_id
    end)
  end

  # Private helpers

  defp resolve_loot_by_rules(creature_id) do
    rules = get_creature_loot_rules()

    if rules do
      case Core.get(:creatures, creature_id) do
        {:ok, creature} ->
          race_id = creature.race_id
          tier_id = creature.tier_id
          difficulty_id = creature.difficulty_id

          race_mappings = get_rule_map(rules, :race_mappings)
          tier_modifiers = get_rule_map(rules, :tier_modifiers)
          difficulty_modifiers = get_rule_map(rules, :difficulty_modifiers)

          race_mapping = get_rule_value(race_mappings, race_id, %{base_table: 1})
          base_table = get_map_value(race_mapping, :base_table, 1)

          tier_mod = get_rule_value(tier_modifiers, tier_id, %{})
          diff_mod = get_rule_value(difficulty_modifiers, difficulty_id, %{})

          table_offset = get_map_value(tier_mod, :table_offset, 0)
          final_table = base_table + table_offset

          tier_gold_mult = get_map_value(tier_mod, :gold_multiplier, 1.0)
          diff_gold_mult = get_map_value(diff_mod, :gold_multiplier, 1.0)
          final_gold_mult = tier_gold_mult * diff_gold_mult

          tier_drop_bonus = get_map_value(tier_mod, :drop_bonus, 0)
          diff_drop_bonus = get_map_value(diff_mod, :drop_bonus, 0)
          final_drop_bonus = tier_drop_bonus + diff_drop_bonus

          {:ok,
           %{
             loot_table_id: final_table,
             gold_multiplier: final_gold_mult,
             drop_bonus: final_drop_bonus,
             extra_table: get_map_value(tier_mod, :extra_table, nil)
           }}

        :error ->
          {:ok, %{loot_table_id: 1, gold_multiplier: 1.0, drop_bonus: 0}}
      end
    else
      {:ok, %{loot_table_id: 1, gold_multiplier: 1.0, drop_bonus: 0}}
    end
  end

  defp get_rule_map(rules, key) when is_atom(key) do
    Map.get(rules, key) || Map.get(rules, Atom.to_string(key), %{})
  end

  defp get_rule_value(rule_map, key, default) when is_integer(key) do
    str_key = Integer.to_string(key)

    Map.get(rule_map, key) ||
      Map.get(rule_map, str_key) ||
      Map.get(rule_map, String.to_atom(str_key)) ||
      Map.get(rule_map, :default) ||
      Map.get(rule_map, "default", default)
  end

  defp get_map_value(map, key, default) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key), default)
      value -> value
    end
  end
end
