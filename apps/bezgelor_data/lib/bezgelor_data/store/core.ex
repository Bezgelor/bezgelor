defmodule BezgelorData.Store.Core do
  @moduledoc """
  Core ETS operations for the Store.

  Provides generic get/list/paginated/count operations that work across all
  ETS tables. These are the fundamental building blocks used by domain-specific
  query modules.

  ## Usage

  These functions are typically called via the main `BezgelorData.Store` module
  which delegates to this module for backwards compatibility.

  ## Table Naming

  All ETS tables follow the naming convention `bezgelor_data_<table>` where
  `<table>` is the logical table name (e.g., `:creatures`, `:spells`).
  """

  @default_page_size 100

  @doc """
  Convert a logical table name to the actual ETS table name.

  ## Examples

      iex> table_name(:creatures)
      :bezgelor_data_creatures
  """
  @spec table_name(atom()) :: atom()
  def table_name(table), do: :"bezgelor_data_#{table}"

  @doc """
  Get an item by ID from the specified table.

  Returns `{:ok, data}` if found, `:error` if not found or table doesn't exist.
  """
  @spec get(atom(), non_neg_integer()) :: {:ok, map()} | :error
  def get(table, id) do
    ets_table = table_name(table)

    case :ets.info(ets_table) do
      :undefined ->
        :error

      _ ->
        case :ets.lookup(ets_table, id) do
          [{^id, data}] -> {:ok, data}
          [] -> :error
        end
    end
  end

  @doc """
  List all items from the specified table.

  Note: For large tables, consider using `list_paginated/2` instead to avoid
  loading 50,000+ items into memory at once.
  """
  @spec list(atom()) :: [map()]
  def list(table) do
    :ets.tab2list(table_name(table))
    |> Enum.map(fn {_id, data} -> data end)
  end

  @doc """
  List items with pagination.

  Returns `{items, continuation}` where continuation is nil when no more pages.
  Uses ETS match with continuation for memory-efficient iteration over large tables.

  ## Example

      {items, cont} = Store.Core.list_paginated(:items, 50)
      {more_items, cont2} = Store.Core.list_continue(cont)
  """
  @spec list_paginated(atom(), pos_integer()) :: {[map()], term() | nil}
  def list_paginated(table, limit \\ @default_page_size) do
    ets_table = table_name(table)

    case :ets.match(ets_table, {:"$1", :"$2"}, limit) do
      {matches, continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Continue paginated iteration from a previous call.

  Returns `{items, continuation}` where continuation is nil when no more pages.
  """
  @spec list_continue(term()) :: {[map()], term() | nil}
  def list_continue(nil), do: {[], nil}

  def list_continue(continuation) do
    case :ets.match(continuation) do
      {matches, new_continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, new_continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  List items matching a filter with pagination.

  Uses `:ets.select/3` for efficient server-side iteration with filtering
  applied in-memory. For simple equality filters on indexed fields,
  consider using a specific query function instead.
  """
  @spec list_filtered(atom(), (map() -> boolean()), pos_integer()) :: {[map()], term() | nil}
  def list_filtered(table, filter_fn, limit \\ @default_page_size) do
    ets_table = table_name(table)

    match_spec = [
      {
        {:"$1", :"$2"},
        [],
        [:"$2"]
      }
    ]

    case :ets.select(ets_table, match_spec, limit) do
      {items, continuation} ->
        filtered = Enum.filter(items, filter_fn)
        {filtered, {:filtered, continuation, filter_fn}}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Continue filtered pagination from a previous call.
  """
  @spec list_filtered_continue(term()) :: {[map()], term() | nil}
  def list_filtered_continue(nil), do: {[], nil}

  def list_filtered_continue({:filtered, continuation, filter_fn}) do
    case :ets.select(continuation) do
      {items, new_continuation} ->
        filtered = Enum.filter(items, filter_fn)
        {filtered, {:filtered, new_continuation, filter_fn}}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Collect all pages into a list (convenience function for small filtered results).

  Use with caution on large tables - this will load all matching items into memory.
  """
  @spec collect_all_pages({[map()], term() | nil}, (term() -> {[map()], term() | nil})) :: [map()]
  def collect_all_pages({items, nil}, _continue_fn), do: items

  def collect_all_pages({items, continuation}, continue_fn) do
    items ++ collect_all_pages(continue_fn.(continuation), continue_fn)
  end

  @doc """
  Get the count of items in a table.
  """
  @spec count(atom()) :: non_neg_integer()
  def count(table) do
    :ets.info(table_name(table), :size)
  end
end
