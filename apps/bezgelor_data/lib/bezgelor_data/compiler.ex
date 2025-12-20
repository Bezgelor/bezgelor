defmodule BezgelorData.Compiler do
  @moduledoc """
  Compiles JSON data files to ETF (Erlang Term Format) for faster loading.

  JSON files in priv/data/ are the source of truth and kept in git.
  ETF files in priv/compiled/ are generated on first load and gitignored.

  Compilation strategy:
  - Compare mtimes of JSON source and ETF output
  - If ETF is missing or stale, recompile from JSON
  - Use :erlang.term_to_binary with compression for ETF output
  """

  require Logger

  @data_files [
    {"creatures.json", "creatures", "creatures.etf"},
    {"zones.json", "zones", "zones.etf"},
    {"spells.json", "spells", "spells.etf"},
    {"items.json", "items", "items.etf"},
    {"texts.json", "texts", "texts.etf"}
  ]

  @doc """
  Compile all JSON files to ETF if needed.
  Returns :ok if all files are up to date or compiled successfully.
  """
  @spec compile_all() :: :ok | {:error, term()}
  def compile_all do
    data_dir = data_directory()
    compiled_dir = compiled_directory()

    # Ensure compiled directory exists
    File.mkdir_p!(compiled_dir)

    results =
      for {json_file, _key, etf_file} <- @data_files do
        json_path = Path.join(data_dir, json_file)
        etf_path = Path.join(compiled_dir, etf_file)
        compile_if_stale(json_path, etf_path)
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  @doc """
  Compile a single JSON file to ETF if the ETF is missing or stale.
  """
  @spec compile_if_stale(String.t(), String.t()) :: :ok | {:error, term()}
  def compile_if_stale(json_path, etf_path) do
    if needs_recompile?(json_path, etf_path) do
      compile(json_path, etf_path)
    else
      :ok
    end
  end

  @doc """
  Check if ETF needs to be recompiled from JSON.
  Returns true if ETF is missing or older than JSON.
  """
  @spec needs_recompile?(String.t(), String.t()) :: boolean()
  def needs_recompile?(json_path, etf_path) do
    case {File.stat(json_path), File.stat(etf_path)} do
      {{:ok, json_stat}, {:ok, etf_stat}} ->
        json_stat.mtime > etf_stat.mtime

      {{:ok, _json_stat}, {:error, :enoent}} ->
        true

      _ ->
        # JSON missing or other error - don't try to compile
        false
    end
  end

  @doc """
  Compile a JSON file to ETF format.
  """
  @spec compile(String.t(), String.t()) :: :ok | {:error, term()}
  def compile(json_path, etf_path) do
    Logger.info("Compiling #{Path.basename(json_path)} -> #{Path.basename(etf_path)}")

    with {:ok, json_content} <- File.read(json_path),
         {:ok, data} <- Jason.decode(json_content, keys: :atoms) do
      # Convert to ETF with compression
      etf_content = :erlang.term_to_binary(data, [:compressed])

      case File.write(etf_path, etf_content) do
        :ok ->
          Logger.debug(
            "Compiled #{byte_size(json_content)} bytes JSON -> #{byte_size(etf_content)} bytes ETF"
          )

          :ok

        {:error, reason} ->
          {:error, {:write_failed, etf_path, reason}}
      end
    else
      {:error, :enoent} ->
        {:error, {:file_not_found, json_path}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:json_decode_error, json_path, error}}

      {:error, reason} ->
        {:error, {:read_failed, json_path, reason}}
    end
  end

  @doc """
  Load data from ETF file, falling back to JSON if ETF is unavailable.
  Compiles ETF on the fly if JSON is available but ETF is not.
  """
  @spec load_data(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_data(json_file, key) do
    data_dir = data_directory()
    compiled_dir = compiled_directory()

    etf_file = String.replace_suffix(json_file, ".json", ".etf")
    json_path = Path.join(data_dir, json_file)
    etf_path = Path.join(compiled_dir, etf_file)

    # Ensure compiled directory exists
    File.mkdir_p!(compiled_dir)

    # Compile if needed
    case compile_if_stale(json_path, etf_path) do
      :ok -> :ok
      {:error, _} = error -> Logger.warning("Compilation failed: #{inspect(error)}")
    end

    # Try loading ETF first, fall back to JSON
    case load_etf(etf_path, key) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        Logger.debug("Falling back to JSON: #{json_file}")
        load_json(json_path, key)
    end
  end

  @doc """
  Load data from ETF file.
  """
  @spec load_etf(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_etf(etf_path, key) do
    with {:ok, content} <- File.read(etf_path),
         {:ok, data} <- safe_binary_to_term(content) do
      items = Map.get(data, String.to_atom(key), [])
      {:ok, items}
    end
  end

  @doc """
  Load data from JSON file.
  """
  @spec load_json(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_json(json_path, key) do
    with {:ok, content} <- File.read(json_path),
         {:ok, data} <- Jason.decode(content, keys: :atoms) do
      items = Map.get(data, String.to_atom(key), [])
      {:ok, items}
    end
  end

  # Safely convert binary to term, catching any errors
  defp safe_binary_to_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      ArgumentError -> {:error, :invalid_etf}
    end
  end

  defp data_directory do
    Application.app_dir(:bezgelor_data, "priv/data")
  end

  defp compiled_directory do
    Application.app_dir(:bezgelor_data, "priv/compiled")
  end
end
