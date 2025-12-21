defmodule BezgelorData.Queries.Instances do
  @moduledoc """
  Query functions for instance/dungeon data: dungeons, raids, bosses, mythic+ affixes.
  """

  alias BezgelorData.Store

  # Instance queries

  @doc """
  Get an instance definition by ID.
  """
  @spec get_instance(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance(id), do: Store.get(:instances, id)

  @doc """
  Get all instances of a specific type.

  Uses secondary index for O(1) lookup instead of scanning all instances.
  """
  @spec get_instances_by_type(String.t()) :: [map()]
  def get_instances_by_type(type) when type in ["dungeon", "adventure", "raid", "expedition"] do
    ids = Store.lookup_index(:instances_by_type, type)
    Store.fetch_by_ids(:instances, ids)
  end

  @doc """
  Get instances available for a player level.
  """
  @spec get_available_instances(non_neg_integer()) :: [map()]
  def get_available_instances(player_level) do
    Store.list(:instances)
    |> Enum.filter(fn i -> i.min_level <= player_level and i.max_level >= player_level end)
  end

  @doc """
  Get instances with a specific difficulty.
  """
  @spec get_instances_with_difficulty(String.t()) :: [map()]
  def get_instances_with_difficulty(difficulty) do
    Store.list(:instances)
    |> Enum.filter(fn i -> difficulty in i.difficulties end)
  end

  # Instance boss queries

  @doc """
  Get an instance boss definition by ID.
  """
  @spec get_instance_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance_boss(id), do: Store.get(:instance_bosses, id)

  @doc """
  Get all bosses for an instance.

  Uses secondary index for O(1) lookup instead of scanning all bosses.
  """
  @spec get_bosses_for_instance(non_neg_integer()) :: [map()]
  def get_bosses_for_instance(instance_id) do
    ids = Store.lookup_index(:bosses_by_instance, instance_id)

    Store.fetch_by_ids(:instance_bosses, ids)
    |> Enum.sort_by(fn b -> b.order end)
  end

  @doc """
  Get required bosses for an instance (non-optional).
  """
  @spec get_required_bosses(non_neg_integer()) :: [map()]
  def get_required_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> not b.is_optional end)
  end

  @doc """
  Get optional bosses for an instance.
  """
  @spec get_optional_bosses(non_neg_integer()) :: [map()]
  def get_optional_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> b.is_optional end)
  end

  # Mythic+ affix queries

  @doc """
  Get a mythic affix by ID.
  """
  @spec get_mythic_affix(non_neg_integer()) :: {:ok, map()} | :error
  def get_mythic_affix(id), do: Store.get(:mythic_affixes, id)

  @doc """
  Get all mythic affixes.
  """
  @spec get_all_mythic_affixes() :: [map()]
  def get_all_mythic_affixes, do: Store.list(:mythic_affixes)

  @doc """
  Get affixes available at a keystone level.
  """
  @spec get_affixes_for_level(non_neg_integer()) :: [map()]
  def get_affixes_for_level(keystone_level) do
    Store.list(:mythic_affixes)
    |> Enum.filter(fn a -> a.min_level <= keystone_level end)
  end

  @doc """
  Get affixes by tier.
  """
  @spec get_affixes_by_tier(non_neg_integer()) :: [map()]
  def get_affixes_by_tier(tier) when tier in 1..4 do
    Store.list(:mythic_affixes)
    |> Enum.filter(fn a -> a.tier == tier end)
  end

  @doc """
  Get the weekly affix rotation for a given week.
  Returns nil if week is out of range or data not loaded.
  """
  @spec get_weekly_affix_rotation(non_neg_integer()) :: [map()] | nil
  def get_weekly_affix_rotation(week) when week >= 1 and week <= 12 do
    case :ets.lookup(Store.table_name(:mythic_affixes), :weekly_rotation) do
      [{:weekly_rotation, rotations}] ->
        rotation = Enum.find(rotations, fn r -> r.week == week end)

        if rotation do
          Enum.map(rotation.affixes, fn affix_id ->
            case get_mythic_affix(affix_id) do
              {:ok, affix} -> affix
              :error -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
        else
          nil
        end

      [] ->
        nil
    end
  end

  def get_weekly_affix_rotation(_week), do: nil
end
