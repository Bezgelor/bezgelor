defmodule BezgelorData.Queries.PvP do
  @moduledoc """
  Query functions for PvP data: battlegrounds, arenas, warplots.
  """

  alias BezgelorData.Store

  # Battleground queries

  @doc """
  Get a battleground definition by ID.
  """
  @spec get_battleground(non_neg_integer()) :: {:ok, map()} | :error
  def get_battleground(id), do: Store.get(:battlegrounds, id)

  @doc """
  Get all battlegrounds.
  """
  @spec get_all_battlegrounds() :: [map()]
  def get_all_battlegrounds, do: Store.list(:battlegrounds)

  @doc """
  Get battlegrounds available for a player level.
  """
  @spec get_available_battlegrounds(non_neg_integer()) :: [map()]
  def get_available_battlegrounds(player_level) do
    Store.list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.min_level <= player_level and bg.max_level >= player_level end)
  end

  @doc """
  Get battlegrounds by type.
  """
  @spec get_battlegrounds_by_type(String.t()) :: [map()]
  def get_battlegrounds_by_type(type) do
    Store.list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.type == type end)
  end

  # Arena queries

  @doc """
  Get an arena definition by ID.
  """
  @spec get_arena(non_neg_integer()) :: {:ok, map()} | :error
  def get_arena(id), do: Store.get(:arenas, id)

  @doc """
  Get all arenas.
  """
  @spec get_all_arenas() :: [map()]
  def get_all_arenas, do: Store.list(:arenas)

  @doc """
  Get arenas that support a specific bracket.
  """
  @spec get_arenas_for_bracket(String.t()) :: [map()]
  def get_arenas_for_bracket(bracket) do
    Store.list(:arenas)
    |> Enum.filter(fn arena -> bracket in arena.brackets end)
  end

  @doc """
  Get arena bracket configuration.
  Returns nil if bracket data not loaded or bracket not found.
  """
  @spec get_arena_bracket(String.t()) :: map() | nil
  def get_arena_bracket(bracket) do
    case :ets.lookup(Store.table_name(:arenas), :brackets) do
      [{:brackets, brackets}] -> Map.get(brackets, String.to_atom(bracket))
      [] -> nil
    end
  end

  @doc """
  Get arena rating rewards configuration.
  """
  @spec get_arena_rating_rewards() :: map() | nil
  def get_arena_rating_rewards do
    case :ets.lookup(Store.table_name(:arenas), :rating_rewards) do
      [{:rating_rewards, rewards}] -> rewards
      [] -> nil
    end
  end

  # Warplot queries

  @doc """
  Get a warplot plug definition by ID.
  """
  @spec get_warplot_plug(non_neg_integer()) :: {:ok, map()} | :error
  def get_warplot_plug(id), do: Store.get(:warplot_plugs, id)

  @doc """
  Get all warplot plugs.
  """
  @spec get_all_warplot_plugs() :: [map()]
  def get_all_warplot_plugs, do: Store.list(:warplot_plugs)

  @doc """
  Get warplot plugs by category.
  """
  @spec get_warplot_plugs_by_category(String.t()) :: [map()]
  def get_warplot_plugs_by_category(category) do
    Store.list(:warplot_plugs)
    |> Enum.filter(fn plug -> plug.category == category end)
  end

  @doc """
  Get warplot plug categories with descriptions.
  """
  @spec get_warplot_plug_categories() :: map() | nil
  def get_warplot_plug_categories do
    case :ets.lookup(Store.table_name(:warplot_plugs), :categories) do
      [{:categories, categories}] -> categories
      [] -> nil
    end
  end

  @doc """
  Get warplot socket layout.
  """
  @spec get_warplot_socket_layout() :: map() | nil
  def get_warplot_socket_layout do
    case :ets.lookup(Store.table_name(:warplot_plugs), :socket_layout) do
      [{:socket_layout, layout}] -> layout
      [] -> nil
    end
  end

  @doc """
  Get warplot settings.
  """
  @spec get_warplot_settings() :: map() | nil
  def get_warplot_settings do
    case :ets.lookup(Store.table_name(:warplot_plugs), :warplot_settings) do
      [{:warplot_settings, settings}] -> settings
      [] -> nil
    end
  end
end
