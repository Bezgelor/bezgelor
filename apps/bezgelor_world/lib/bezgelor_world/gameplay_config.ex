defmodule BezgelorWorld.GameplayConfig do
  @moduledoc """
  Access gameplay configuration values.

  Settings are stored in the application environment under `:bezgelor_world, :gameplay`.
  See `docs/bezgelor-vs-wildstar.md` for details on retail vs private server differences.
  """

  @doc """
  Schema for gameplay settings with types, descriptions, and constraints.
  Used by ServerConfig for validation and admin UI display.
  """
  @spec schema() :: map()
  def schema do
    %{
      unlock_all_specs: %{
        type: :boolean,
        description: "Unlock all 4 action set specs immediately for new characters",
        impact: :new_characters_only,
        default: true
      },
      default_tier_points: %{
        type: :integer,
        description: "Default ability tier points for new characters (max 42)",
        impact: :new_characters_only,
        constraints: %{min: 0, max: 42},
        default: 42
      },
      auto_place_starter_abilities: %{
        type: :boolean,
        description: "Auto-place starter abilities on new character action bars",
        impact: :new_characters_only,
        default: true
      }
    }
  end

  @doc """
  Get all gameplay config values as a keyword list.
  """
  @spec get_all() :: keyword()
  def get_all do
    Application.get_env(:bezgelor_world, :gameplay, [])
  end

  @doc """
  Get a gameplay config value.
  """
  @spec get(atom()) :: term()
  def get(key) do
    config = Application.get_env(:bezgelor_world, :gameplay, [])
    Keyword.get(config, key)
  end

  @doc "Whether to unlock all 4 action set specs immediately. Defaults to true."
  @spec unlock_all_specs?() :: boolean()
  def unlock_all_specs?, do: get(:unlock_all_specs) != false

  @doc "Default tier points granted to new characters. Defaults to 42 (max)."
  @spec default_tier_points() :: non_neg_integer()
  def default_tier_points, do: get(:default_tier_points) || 42

  @doc "Whether starter abilities are auto-placed on action bar. Defaults to true."
  @spec auto_place_starter_abilities?() :: boolean()
  def auto_place_starter_abilities?, do: get(:auto_place_starter_abilities) != false
end
