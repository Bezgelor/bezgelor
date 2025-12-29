defmodule BezgelorData.Store.Index do
  @moduledoc """
  Secondary index management for the Store.

  Provides functions for building and querying secondary indexes that enable
  efficient lookups by foreign keys (e.g., quests by zone, spells by creature).

  ## Index Structure

  Each index is stored in a separate ETS table with naming convention
  `bezgelor_index_<name>`. Index entries map a key value to a list of
  primary IDs that match that key.

  ## Usage

  Indexes are built during Store initialization and can be queried using
  `lookup_index/2` to get matching IDs, then `fetch_by_ids/2` to retrieve
  the full records.
  """

  require Logger

  alias BezgelorData.Store.Core

  @doc """
  Convert a logical index table name to the actual ETS table name.
  """
  @spec index_table_name(atom()) :: atom()
  def index_table_name(table), do: :"bezgelor_index_#{table}"

  @doc """
  Lookup IDs from a secondary index table.

  Returns empty list if key not found. Used by query modules to perform
  indexed lookups before fetching full records.
  """
  @spec lookup_index(atom(), term()) :: [non_neg_integer()]
  def lookup_index(index_table, key) do
    case :ets.lookup(index_table_name(index_table), key) do
      [{^key, ids}] -> ids
      [] -> []
    end
  end

  @doc """
  Fetch full records from a table for a list of IDs.

  Returns only the records that exist (nil results are filtered out).
  Used by query modules after looking up IDs from an index.
  """
  @spec fetch_by_ids(atom(), [non_neg_integer()]) :: [map()]
  def fetch_by_ids(table, ids) do
    table_name = Core.table_name(table)

    ids
    |> Enum.map(fn id ->
      case :ets.lookup(table_name, id) do
        [{^id, data}] -> data
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Build a secondary index from a source table using an integer key field.

  Groups all records by the specified key field and stores the mapping
  from key value to list of primary IDs.
  """
  @spec build_index(atom(), atom(), atom()) :: :ok
  def build_index(source_table, index_table, key_field) do
    source_name = Core.table_name(source_table)
    index_name = index_table_name(index_table)

    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)
      |> Enum.filter(fn {key, _ids} -> not is_nil(key) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
    :ok
  end

  @doc """
  Build a secondary index using a string key field.

  Same as `build_index/3` but accepts string key values.
  """
  @spec build_index_string(atom(), atom(), atom()) :: :ok
  def build_index_string(source_table, index_table, key_field) do
    source_name = Core.table_name(source_table)
    index_name = index_table_name(index_table)

    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)
      |> Enum.filter(fn {key, _ids} -> not is_nil(key) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
    :ok
  end

  @doc """
  Build a composite index using multiple key fields as a tuple key.

  Creates an index where the key is a tuple of values from multiple fields.
  Useful for lookups like "zones in world X".
  """
  @spec build_composite_index(atom(), atom(), [atom()]) :: :ok
  def build_composite_index(source_table, index_table, key_fields) do
    source_name = Core.table_name(source_table)
    index_name = index_table_name(index_table)

    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(
        fn {_id, data} ->
          Enum.map(key_fields, &Map.get(data, &1)) |> List.to_tuple()
        end,
        fn {id, _data} -> id end
      )
      |> Enum.filter(fn {key, _ids} -> not Enum.any?(Tuple.to_list(key), &is_nil/1) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
    :ok
  end
end
