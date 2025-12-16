defmodule BezgelorData.Queries.Achievements do
  @moduledoc """
  Query functions for achievement and path data.
  """

  alias BezgelorData.Store

  # Achievement queries

  @doc """
  Get an achievement by ID.
  """
  @spec get_achievement(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement(id), do: Store.get(:achievements, id)

  @doc """
  Get achievements for a category.
  Uses secondary index for O(1) lookup.
  """
  @spec get_achievements_for_category(non_neg_integer()) :: [map()]
  def get_achievements_for_category(category_id) do
    ids = Store.lookup_index(:achievements_by_category, category_id)
    Store.fetch_by_ids(:achievements, ids)
  end

  @doc """
  Get achievements for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_achievements_for_zone(non_neg_integer()) :: [map()]
  def get_achievements_for_zone(zone_id) do
    ids = Store.lookup_index(:achievements_by_zone, zone_id)
    Store.fetch_by_ids(:achievements, ids)
  end

  @doc """
  Get an achievement category by ID.
  """
  @spec get_achievement_category(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement_category(id), do: Store.get(:achievement_categories, id)

  @doc """
  Get achievement checklist items for an achievement.
  """
  @spec get_achievement_checklists(non_neg_integer()) :: [map()]
  def get_achievement_checklists(achievement_id) do
    Store.list(:achievement_checklists)
    |> Enum.filter(fn c -> c.achievementId == achievement_id end)
    |> Enum.sort_by(fn c -> c.bit end)
  end

  # Path queries

  @doc """
  Get a path mission by ID.
  """
  @spec get_path_mission(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_mission(id), do: Store.get(:path_missions, id)

  @doc """
  Get path missions for an episode.
  Uses secondary index for O(1) lookup.
  """
  @spec get_path_missions_for_episode(non_neg_integer()) :: [map()]
  def get_path_missions_for_episode(episode_id) do
    ids = Store.lookup_index(:path_missions_by_episode, episode_id)
    Store.fetch_by_ids(:path_missions, ids)
  end

  @doc """
  Get path missions by path type.
  Uses secondary index for O(1) lookup.
  """
  @spec get_path_missions_by_type(non_neg_integer()) :: [map()]
  def get_path_missions_by_type(path_type) do
    ids = Store.lookup_index(:path_missions_by_type, path_type)
    Store.fetch_by_ids(:path_missions, ids)
  end

  @doc """
  Get a path episode by ID.
  """
  @spec get_path_episode(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_episode(id), do: Store.get(:path_episodes, id)

  @doc """
  Get a path reward by ID.
  """
  @spec get_path_reward(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_reward(id), do: Store.get(:path_rewards, id)

  @doc """
  Get path episodes for a zone.
  Uses secondary index for O(1) lookup on both world and zone.
  """
  @spec get_path_episodes_for_zone(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_path_episodes_for_zone(world_id, zone_id) do
    ids = Store.lookup_index(:path_episodes_by_zone, {world_id, zone_id})
    Store.fetch_by_ids(:path_episodes, ids)
  end

  @doc """
  Get path missions for a zone and path type.
  """
  @spec get_zone_path_missions(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: [map()]
  def get_zone_path_missions(world_id, zone_id, path_type) do
    get_path_episodes_for_zone(world_id, zone_id)
    |> Enum.flat_map(fn ep ->
      get_path_missions_for_episode(ep.id)
    end)
    |> Enum.filter(fn m -> m.path_type == path_type end)
  end

  # Challenge queries

  @doc """
  Get a challenge by ID.
  """
  @spec get_challenge(non_neg_integer()) :: {:ok, map()} | :error
  def get_challenge(id), do: Store.get(:challenges, id)

  @doc """
  Get challenges for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_challenges_for_zone(non_neg_integer()) :: [map()]
  def get_challenges_for_zone(zone_id) do
    ids = Store.lookup_index(:challenges_by_zone, zone_id)
    Store.fetch_by_ids(:challenges, ids)
  end

  @doc """
  Get a challenge tier by ID.
  """
  @spec get_challenge_tier(non_neg_integer()) :: {:ok, map()} | :error
  def get_challenge_tier(id), do: Store.get(:challenge_tiers, id)
end
