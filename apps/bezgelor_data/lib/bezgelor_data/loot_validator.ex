defmodule BezgelorData.LootValidator do
  @moduledoc """
  Validates loot table data and creature loot rules.

  Called during data loading to ensure data integrity and provide
  early warning of configuration errors.
  """

  require Logger

  @doc """
  Validate all loot data (tables and rules).

  Returns {:ok, stats} on success or {:error, errors} if validation fails.
  """
  @spec validate_all() :: {:ok, map()} | {:error, [String.t()]}
  def validate_all do
    table_result = validate_loot_tables()
    rules_result = validate_loot_rules()

    errors =
      case {table_result, rules_result} do
        {{:ok, _}, {:ok, _}} -> []
        {{:error, t_errs}, {:ok, _}} -> t_errs
        {{:ok, _}, {:error, r_errs}} -> r_errs
        {{:error, t_errs}, {:error, r_errs}} -> t_errs ++ r_errs
      end

    if errors == [] do
      stats = %{
        tables: elem(table_result, 1),
        rules: elem(rules_result, 1)
      }

      {:ok, stats}
    else
      {:error, errors}
    end
  end

  @doc """
  Validate loot tables structure and values.
  """
  @spec validate_loot_tables() :: {:ok, map()} | {:error, [String.t()]}
  def validate_loot_tables do
    tables = BezgelorData.Store.get_all_loot_tables()

    if tables == [] do
      {:error, ["No loot tables loaded"]}
    else
      {valid_tables, errors} =
        Enum.reduce(tables, {0, []}, fn table, {count, errs} ->
          case validate_loot_table(table) do
            :ok -> {count + 1, errs}
            {:error, table_errors} -> {count, errs ++ table_errors}
          end
        end)

      if errors == [] do
        {:ok, %{table_count: valid_tables, entry_count: count_entries(tables)}}
      else
        {:error, errors}
      end
    end
  end

  @doc """
  Validate creature loot rules structure.
  """
  @spec validate_loot_rules() :: {:ok, map()} | {:error, [String.t()]}
  def validate_loot_rules do
    rules = BezgelorData.Store.get_creature_loot_rules()

    if is_nil(rules) do
      {:error, ["No creature loot rules loaded"]}
    else
      errors = []

      # Validate race_mappings
      race_mappings = get_rule_section(rules, :race_mappings)
      race_errors = validate_race_mappings(race_mappings)

      # Validate tier_modifiers
      tier_modifiers = get_rule_section(rules, :tier_modifiers)
      tier_errors = validate_tier_modifiers(tier_modifiers)

      # Validate difficulty_modifiers
      diff_modifiers = get_rule_section(rules, :difficulty_modifiers)
      diff_errors = validate_difficulty_modifiers(diff_modifiers)

      # Validate table references exist
      ref_errors = validate_table_references(race_mappings, tier_modifiers)

      all_errors = errors ++ race_errors ++ tier_errors ++ diff_errors ++ ref_errors

      if all_errors == [] do
        stats = %{
          race_mappings: map_size(race_mappings),
          tier_modifiers: map_size(tier_modifiers),
          difficulty_modifiers: map_size(diff_modifiers)
        }

        {:ok, stats}
      else
        {:error, all_errors}
      end
    end
  end

  # Private validation functions

  defp validate_loot_table(table) do
    errors = []
    table_id = Map.get(table, :id)

    # Check required fields
    errors =
      if is_nil(table_id) or not is_integer(table_id) do
        ["Loot table missing valid :id" | errors]
      else
        errors
      end

    errors =
      if is_nil(Map.get(table, :name)) do
        ["Loot table #{table_id || "?"} missing :name" | errors]
      else
        errors
      end

    entries = Map.get(table, :entries, [])

    errors =
      if not is_list(entries) do
        ["Loot table #{table_id} :entries is not a list" | errors]
      else
        entry_errors =
          entries
          |> Enum.with_index()
          |> Enum.flat_map(fn {entry, idx} ->
            validate_loot_entry(entry, table_id, idx)
          end)

        errors ++ entry_errors
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp validate_loot_entry(entry, table_id, idx) do
    errors = []
    prefix = "Table #{table_id} entry #{idx}"

    # item_id should be non-negative integer
    item_id = get_entry_value(entry, :item_id)

    errors =
      if is_nil(item_id) or not is_integer(item_id) or item_id < 0 do
        ["#{prefix}: invalid item_id (#{inspect(item_id)})" | errors]
      else
        errors
      end

    # chance should be 1-100
    chance = get_entry_value(entry, :chance)

    errors =
      if is_nil(chance) or not is_number(chance) or chance < 1 or chance > 100 do
        ["#{prefix}: invalid chance (#{inspect(chance)}), must be 1-100" | errors]
      else
        errors
      end

    # min should be positive integer
    min = get_entry_value(entry, :min)

    errors =
      if is_nil(min) or not is_integer(min) or min < 1 do
        ["#{prefix}: invalid min (#{inspect(min)}), must be >= 1" | errors]
      else
        errors
      end

    # max should be >= min
    max = get_entry_value(entry, :max)

    errors =
      if is_nil(max) or not is_integer(max) or max < 1 do
        ["#{prefix}: invalid max (#{inspect(max)}), must be >= 1" | errors]
      else
        if min && max && max < min do
          ["#{prefix}: max (#{max}) < min (#{min})" | errors]
        else
          errors
        end
      end

    # type should be "gold" or "item"
    type = get_entry_value(entry, :type)

    errors =
      if type not in ["gold", "item", :gold, :item] do
        ["#{prefix}: invalid type (#{inspect(type)}), must be 'gold' or 'item'" | errors]
      else
        errors
      end

    errors
  end

  defp validate_race_mappings(mappings) when map_size(mappings) == 0 do
    ["race_mappings is empty"]
  end

  defp validate_race_mappings(mappings) do
    mappings
    |> Enum.reject(fn {key, _} -> metadata_key?(key) end)
    |> Enum.flat_map(fn {key, value} ->
      validate_race_mapping_entry(key, value)
    end)
  end

  # Keys starting with underscore are metadata/documentation, not config
  defp metadata_key?(key) when is_atom(key), do: String.starts_with?(Atom.to_string(key), "_")
  defp metadata_key?(key) when is_binary(key), do: String.starts_with?(key, "_")
  defp metadata_key?(_), do: false

  defp validate_race_mapping_entry(key, value) do
    errors = []
    prefix = "race_mapping[#{key}]"

    # Must have base_table
    base_table = get_map_value(value, :base_table)

    errors =
      if is_nil(base_table) do
        ["#{prefix}: missing base_table" | errors]
      else
        if not is_integer(base_table) or base_table < 0 do
          ["#{prefix}: invalid base_table (#{inspect(base_table)})" | errors]
        else
          errors
        end
      end

    errors
  end

  defp validate_tier_modifiers(modifiers) when map_size(modifiers) == 0 do
    ["tier_modifiers is empty"]
  end

  defp validate_tier_modifiers(modifiers) do
    modifiers
    |> Enum.reject(fn {key, _} -> metadata_key?(key) end)
    |> Enum.flat_map(fn {key, value} ->
      validate_modifier_entry("tier_modifier", key, value)
    end)
  end

  defp validate_difficulty_modifiers(modifiers) when map_size(modifiers) == 0 do
    ["difficulty_modifiers is empty"]
  end

  defp validate_difficulty_modifiers(modifiers) do
    modifiers
    |> Enum.reject(fn {key, _} -> metadata_key?(key) end)
    |> Enum.flat_map(fn {key, value} ->
      validate_modifier_entry("difficulty_modifier", key, value)
    end)
  end

  defp validate_modifier_entry(type, key, value) do
    errors = []
    prefix = "#{type}[#{key}]"

    # gold_multiplier should be positive number
    gold_mult = get_map_value(value, :gold_multiplier)

    errors =
      if not is_nil(gold_mult) and (not is_number(gold_mult) or gold_mult <= 0) do
        ["#{prefix}: invalid gold_multiplier (#{inspect(gold_mult)})" | errors]
      else
        errors
      end

    # drop_bonus should be number (can be negative for penalties)
    drop_bonus = get_map_value(value, :drop_bonus)

    errors =
      if not is_nil(drop_bonus) and not is_number(drop_bonus) do
        ["#{prefix}: invalid drop_bonus (#{inspect(drop_bonus)})" | errors]
      else
        errors
      end

    # extra_table should be positive integer if present
    extra_table = get_map_value(value, :extra_table)

    errors =
      if not is_nil(extra_table) and (not is_integer(extra_table) or extra_table < 0) do
        ["#{prefix}: invalid extra_table (#{inspect(extra_table)})" | errors]
      else
        errors
      end

    errors
  end

  defp validate_table_references(race_mappings, tier_modifiers) do
    # Collect all table IDs that exist
    existing_table_ids =
      BezgelorData.Store.get_all_loot_tables()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    errors = []

    # Check race_mapping base_tables (skip metadata keys)
    race_errors =
      race_mappings
      |> Enum.reject(fn {key, _} -> metadata_key?(key) end)
      |> Enum.flat_map(fn {key, value} ->
        base_table = get_map_value(value, :base_table)

        if base_table && not MapSet.member?(existing_table_ids, base_table) do
          ["race_mapping[#{key}]: references non-existent table #{base_table}"]
        else
          []
        end
      end)

    # Check tier_modifier extra_tables (skip metadata keys)
    tier_errors =
      tier_modifiers
      |> Enum.reject(fn {key, _} -> metadata_key?(key) end)
      |> Enum.flat_map(fn {key, value} ->
        extra_table = get_map_value(value, :extra_table)

        if extra_table && not MapSet.member?(existing_table_ids, extra_table) do
          ["tier_modifier[#{key}]: references non-existent extra_table #{extra_table}"]
        else
          []
        end
      end)

    errors ++ race_errors ++ tier_errors
  end

  # Helper to get rule section, handling both atom and string keys
  defp get_rule_section(rules, key) when is_atom(key) do
    Map.get(rules, key) || Map.get(rules, Atom.to_string(key), %{})
  end

  # Helper to get entry value, handling both atom and string keys
  defp get_entry_value(entry, key) when is_atom(key) do
    case Map.get(entry, key) do
      nil -> Map.get(entry, Atom.to_string(key))
      value -> value
    end
  end

  # Helper to get map value, handling both atom and string keys
  defp get_map_value(map, key) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      value -> value
    end
  end

  defp count_entries(tables) do
    Enum.reduce(tables, 0, fn table, acc ->
      acc + length(Map.get(table, :entries, []))
    end)
  end
end
