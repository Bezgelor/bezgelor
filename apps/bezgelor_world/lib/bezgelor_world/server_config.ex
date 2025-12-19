defmodule BezgelorWorld.ServerConfig do
  @moduledoc """
  Central configuration system with file persistence.

  Manages runtime-configurable settings across multiple config sections
  (gameplay, tradeskills, etc.). Settings are persisted to JSON and
  survive server restarts.
  """

  require Logger

  @config_dir "priv/config"
  @config_file "server_config.json"

  # Registry of config section modules
  @sections %{
    gameplay: BezgelorWorld.GameplayConfig
  }

  @doc """
  Load configuration from file and merge with defaults.
  Called during application startup.
  """
  @spec load_from_file() :: :ok
  def load_from_file do
    ensure_config_dir()

    case read_config_file() do
      {:ok, config} ->
        apply_config(config)
        Logger.info("ServerConfig: Loaded configuration from #{config_path()}")
        :ok

      {:error, :enoent} ->
        Logger.info("ServerConfig: No config file found, using defaults")
        :ok

      {:error, reason} ->
        Logger.warning("ServerConfig: Failed to load config: #{inspect(reason)}, using defaults")
        :ok
    end
  end

  @doc """
  Get all registered config sections with their schemas and current values.
  """
  @spec list_sections() :: %{atom() => map()}
  def list_sections do
    Map.new(@sections, fn {section_name, module} ->
      {section_name, get_section(section_name, module)}
    end)
  end

  @doc """
  Get a specific config section with schema and current values.
  """
  @spec get_section(atom()) :: map() | nil
  def get_section(section_name) do
    case Map.get(@sections, section_name) do
      nil -> nil
      module -> get_section(section_name, module)
    end
  end

  defp get_section(section_name, module) do
    schema = module.schema()
    current_values = module.get_all()

    settings =
      Map.new(schema, fn {key, meta} ->
        current_value = Keyword.get(current_values, key, meta.default)
        {key, Map.put(meta, :value, current_value)}
      end)

    %{
      name: section_name,
      label: section_label(section_name),
      settings: settings
    }
  end

  @doc """
  Update a setting in a section.
  Validates against schema, updates runtime config, and persists to file.
  """
  @spec update_setting(atom(), atom(), term()) :: :ok | {:error, term()}
  def update_setting(section_name, key, value) do
    with {:ok, module} <- get_section_module(section_name),
         {:ok, validated_value} <- validate_setting(module, key, value),
         :ok <- apply_setting(section_name, key, validated_value),
         :ok <- persist_config() do
      Logger.info("ServerConfig: Updated #{section_name}.#{key} = #{inspect(validated_value)}")
      :ok
    end
  end

  @doc """
  Get the current value of a specific setting.
  """
  @spec get_setting(atom(), atom()) :: {:ok, term()} | {:error, :not_found}
  def get_setting(section_name, key) do
    case get_section(section_name) do
      nil -> {:error, :not_found}
      section ->
        case Map.get(section.settings, key) do
          nil -> {:error, :not_found}
          setting -> {:ok, setting.value}
        end
    end
  end

  # Private functions

  defp get_section_module(section_name) do
    case Map.get(@sections, section_name) do
      nil -> {:error, :unknown_section}
      module -> {:ok, module}
    end
  end

  defp validate_setting(module, key, value) do
    schema = module.schema()

    case Map.get(schema, key) do
      nil ->
        {:error, :unknown_setting}

      meta ->
        validate_value(value, meta)
    end
  end

  defp validate_value(value, %{type: :boolean}) when is_boolean(value), do: {:ok, value}
  defp validate_value("true", %{type: :boolean}), do: {:ok, true}
  defp validate_value("false", %{type: :boolean}), do: {:ok, false}
  defp validate_value(_, %{type: :boolean}), do: {:error, :invalid_boolean}

  defp validate_value(value, %{type: :integer} = meta) when is_integer(value) do
    validate_integer_constraints(value, meta)
  end

  defp validate_value(value, %{type: :integer} = meta) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> validate_integer_constraints(int, meta)
      _ -> {:error, :invalid_integer}
    end
  end

  defp validate_value(_, %{type: :integer}), do: {:error, :invalid_integer}

  defp validate_value(value, %{type: :atom}) when is_atom(value), do: {:ok, value}
  defp validate_value(value, %{type: :atom}) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_atom}
  end

  defp validate_value(_, _), do: {:error, :unsupported_type}

  defp validate_integer_constraints(value, meta) do
    constraints = Map.get(meta, :constraints, %{})
    min = Map.get(constraints, :min)
    max = Map.get(constraints, :max)

    cond do
      min && value < min -> {:error, {:min_value, min}}
      max && value > max -> {:error, {:max_value, max}}
      true -> {:ok, value}
    end
  end

  defp apply_setting(section_name, key, value) do
    app_key = section_app_key(section_name)
    current = Application.get_env(:bezgelor_world, app_key, [])
    updated = Keyword.put(current, key, value)
    Application.put_env(:bezgelor_world, app_key, updated)
    :ok
  end

  defp apply_config(config) do
    # Get valid section names as strings
    valid_sections = Map.keys(@sections) |> Enum.map(&Atom.to_string/1) |> MapSet.new()

    Enum.each(config, fn {section_name, settings} ->
      if MapSet.member?(valid_sections, section_name) do
        section_atom = String.to_existing_atom(section_name)
        module = Map.get(@sections, section_atom)
        schema = module.schema()
        valid_keys = Map.keys(schema) |> Enum.map(&Atom.to_string/1) |> MapSet.new()
        app_key = section_app_key(section_atom)

        # Only apply settings that exist in the schema
        keyword_settings =
          settings
          |> Enum.filter(fn {key, _value} ->
            if MapSet.member?(valid_keys, key) do
              true
            else
              Logger.warning("ServerConfig: Ignoring unknown setting '#{section_name}.#{key}'")
              false
            end
          end)
          |> Enum.map(fn {key, value} ->
            {String.to_existing_atom(key), value}
          end)

        current = Application.get_env(:bezgelor_world, app_key, [])
        merged = Keyword.merge(current, keyword_settings)
        Application.put_env(:bezgelor_world, app_key, merged)
      else
        Logger.warning("ServerConfig: Ignoring unknown section '#{section_name}'")
      end
    end)
  end

  defp persist_config do
    config =
      Map.new(@sections, fn {section_name, module} ->
        values = module.get_all()
        settings_map = Map.new(values, fn {k, v} -> {Atom.to_string(k), v} end)
        {Atom.to_string(section_name), settings_map}
      end)

    json = Jason.encode!(config, pretty: true)

    case File.write(config_path(), json) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("ServerConfig: Failed to persist config: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp read_config_file do
    case File.read(config_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> {:ok, config}
          {:error, _} -> {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config_path do
    app_dir = Application.app_dir(:bezgelor_world)
    Path.join([app_dir, @config_dir, @config_file])
  end

  defp ensure_config_dir do
    dir = Path.join(Application.app_dir(:bezgelor_world), @config_dir)
    File.mkdir_p(dir)
  end

  defp section_app_key(:gameplay), do: :gameplay
  defp section_app_key(:tradeskills), do: :tradeskills
  defp section_app_key(other), do: other

  defp section_label(:gameplay), do: "Gameplay"
  defp section_label(:tradeskills), do: "Tradeskills"
  defp section_label(other), do: other |> Atom.to_string() |> String.capitalize()
end
