defmodule BezgelorData.Store do
  @moduledoc """
  ETS-backed storage for game data.

  Each data type gets its own ETS table for fast concurrent reads.
  Data is loaded at application startup from ETF files (compiled from JSON).
  """

  use GenServer

  require Logger

  alias BezgelorData.Compiler

  @tables [:creatures, :zones, :spells, :items, :texts]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get an item by ID from the specified table.
  """
  @spec get(atom(), non_neg_integer()) :: {:ok, map()} | :error
  def get(table, id) do
    case :ets.lookup(table_name(table), id) do
      [{^id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  List all items from the specified table.
  """
  @spec list(atom()) :: [map()]
  def list(table) do
    :ets.tab2list(table_name(table))
    |> Enum.map(fn {_id, data} -> data end)
  end

  @doc """
  Get the count of items in a table.
  """
  @spec count(atom()) :: non_neg_integer()
  def count(table) do
    :ets.info(table_name(table), :size)
  end

  @doc """
  Reload data from files. Used for development/testing.
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    for table <- @tables do
      :ets.new(table_name(table), [:set, :public, :named_table, read_concurrency: true])
    end

    # Load data
    load_all_data()

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_all_data()
    {:reply, :ok, state}
  end

  # Private functions

  defp table_name(table), do: :"bezgelor_data_#{table}"

  defp load_all_data do
    Logger.info("Loading game data...")

    # Compile all data files if needed
    case Compiler.compile_all() do
      :ok -> Logger.debug("Data compilation complete")
      {:error, reason} -> Logger.warning("Compilation issue: #{inspect(reason)}")
    end

    # Load each table
    load_table(:creatures, "creatures.json", "creatures")
    load_table(:zones, "zones.json", "zones")
    load_table(:spells, "spells.json", "spells")
    load_table(:items, "items.json", "items")
    load_table(:texts, "texts.json", "texts")

    Logger.info("Game data loaded: #{inspect(stats())}")
  end

  defp load_table(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Regular tables have lists of maps with :id
        for item <- items do
          :ets.insert(table_name, {item.id, item})
        end

        Logger.debug("Loaded #{length(items)} #{key}")

      {:ok, items} when is_map(items) ->
        # Texts table is a map of id -> string
        # Keys may be atoms (from :keys => :atoms) or strings
        for {id, text} <- items do
          int_id =
            cond do
              is_integer(id) -> id
              is_binary(id) -> String.to_integer(id)
              is_atom(id) -> id |> Atom.to_string() |> String.to_integer()
            end

          :ets.insert(table_name, {int_id, text})
        end

        Logger.debug("Loaded #{map_size(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end
  end

  defp stats do
    for table <- @tables, into: %{} do
      {table, count(table)}
    end
  end
end
