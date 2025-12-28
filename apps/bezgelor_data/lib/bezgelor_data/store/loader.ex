defmodule BezgelorData.Store.Loader do
  @moduledoc """
  Data loading utilities for the Store.

  Provides generic functions for loading game data from JSON files into ETS tables,
  with ETF caching for faster subsequent loads.

  ## ETF Caching

  JSON files are parsed once and cached as ETF (Erlang Term Format) files in
  `priv/compiled/`. Subsequent loads check if the cache is fresh (based on file
  modification times) and load directly from ETF, which is significantly faster.

  ## Usage

  These functions are called by the Store GenServer during initialization and
  by domain-specific loader functions.
  """

  require Logger

  alias BezgelorData.Store.Core

  @doc """
  Get the data directory path.
  """
  @spec data_directory() :: String.t()
  def data_directory do
    Application.app_dir(:bezgelor_data, "priv/data")
  end

  @doc """
  Get the compiled/cached ETF directory path.
  """
  @spec compiled_directory() :: String.t()
  def compiled_directory do
    Application.app_dir(:bezgelor_data, "priv/compiled")
  end

  @doc """
  Load JSON with ETF caching for faster subsequent loads.

  This is the primary function for loading game data files. It first checks
  for a valid ETF cache and falls back to parsing JSON if the cache is stale.

  ## Security Note

  Uses `keys: :atoms` for JSON parsing which creates atoms from keys.
  This is acceptable because game data files are shipped with the application
  and have known, stable structures. DO NOT use for user-controlled data.
  """
  @spec load_json_raw(String.t()) :: {:ok, map() | list()} | {:error, term()}
  def load_json_raw(path) do
    etf_path = etf_cache_path(path)

    case load_etf_cache(path, etf_path) do
      {:ok, data} ->
        {:ok, data}

      :stale ->
        with {:ok, content} <- File.read(path),
             {:ok, data} <- decode_trusted_json(content) do
          cache_to_etf(etf_path, data)
          {:ok, data}
        end
    end
  end

  @doc """
  Load a simple table with id-keyed records from a JSON file.

  Uses the Compiler module to load data, which handles ETF caching.
  """
  @spec load_table(atom(), String.t(), String.t()) :: :ok
  def load_table(table, json_file, key) do
    table_name = Core.table_name(table)

    :ets.delete_all_objects(table_name)

    case BezgelorData.Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        tuples = Enum.map(items, fn item -> {item.id, item} end)
        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(items)} #{key}")

      {:ok, items} when is_map(items) ->
        tuples =
          Enum.map(items, fn {id, text} ->
            int_id =
              cond do
                is_integer(id) -> id
                is_binary(id) -> String.to_integer(id)
                is_atom(id) -> id |> Atom.to_string() |> String.to_integer()
              end

            {int_id, text}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{map_size(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Load a table indexed by zone_id instead of primary id.
  """
  @spec load_table_by_zone(atom(), String.t(), String.t()) :: :ok
  def load_table_by_zone(table, json_file, key) do
    table_name = Core.table_name(table)

    :ets.delete_all_objects(table_name)

    case BezgelorData.Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        tuples = Enum.map(items, fn item -> {item.zone_id, item} end)
        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Load a table from WildStar client data (uses uppercase ID field).

  Client data uses :ID instead of :id, so this function normalizes the field.
  """
  @spec load_client_table(atom(), String.t(), String.t()) :: :ok
  def load_client_table(table, json_file, key) do
    table_name = Core.table_name(table)

    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), json_file)

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, String.to_atom(key), [])

        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tuples)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key} from #{json_file}: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Load a table from multiple WildStar client data files (for split data).
  """
  @spec load_client_table_parts(atom(), [String.t()], String.t()) :: :ok
  def load_client_table_parts(table, json_files, key) do
    table_name = Core.table_name(table)

    :ets.delete_all_objects(table_name)

    Enum.each(json_files, fn json_file ->
      json_path = Path.join(data_directory(), json_file)

      case load_json_raw(json_path) do
        {:ok, data} ->
          items = Map.get(data, String.to_atom(key), [])

          tuples =
            items
            |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
            |> Enum.map(fn item ->
              id = Map.get(item, :ID)
              normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
              {id, normalized}
            end)

          :ets.insert(table_name, tuples)
          Logger.debug("Loaded #{length(tuples)} #{key} from #{json_file}")

        {:error, reason} ->
          Logger.warning("Failed to load #{key} from #{json_file}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Load client table that needs a foreign key index.
  """
  @spec load_client_table_with_fk(atom(), String.t(), String.t(), atom()) :: :ok
  def load_client_table_with_fk(table, json_file, key, _fk_field) do
    table_name = Core.table_name(table)

    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), json_file)

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, String.to_atom(key), [])

        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tuples)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key} from #{json_file}: #{inspect(reason)}")
    end

    :ok
  end

  # Private helpers

  defp etf_cache_path(json_path) do
    compiled_dir = compiled_directory()
    basename = Path.basename(json_path, ".json") <> ".etf"
    Path.join(compiled_dir, basename)
  end

  defp load_etf_cache(json_path, etf_path) do
    with {:ok, json_stat} <- File.stat(json_path),
         {:ok, etf_stat} <- File.stat(etf_path),
         true <- etf_stat.mtime >= json_stat.mtime,
         {:ok, content} <- File.read(etf_path) do
      try do
        {:ok, :erlang.binary_to_term(content, [:safe])}
      rescue
        _ -> :stale
      end
    else
      _ -> :stale
    end
  end

  defp cache_to_etf(etf_path, data) do
    compiled_dir = Path.dirname(etf_path)
    File.mkdir_p!(compiled_dir)
    etf_content = :erlang.term_to_binary(data, [:compressed])
    File.write(etf_path, etf_content)
  rescue
    _ -> :ok
  end

  # Decode trusted game data JSON with atom keys.
  defp decode_trusted_json(content) do
    Jason.decode(content, keys: :atoms)
  end
end
