defmodule BezgelorData.AchievementIndex do
  @moduledoc """
  Builds and queries event-indexed achievement lookups.

  Index structure:
  - `{:kill, creature_id}` => [achievement_defs]
  - `{:kill, :any}` => [counter achievements]
  - `{:quest_complete, quest_id}` => [achievement_defs]
  - etc.

  This provides O(1) lookup for achievements that match a specific event,
  instead of scanning all 4,943 achievements on every event.
  """

  require Logger

  alias BezgelorData.{AchievementTypes, Store}

  @table :bezgelor_achievement_index

  @doc """
  Build index from loaded achievements. Called at startup.

  Creates an ETS bag table that maps `{event_type, target}` to achievement
  definition maps for fast lookup.
  """
  @spec build_index() :: :ok
  def build_index do
    # Create ETS table if not exists
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end

    # Clear existing entries
    :ets.delete_all_objects(@table)

    # Pre-build set of achievement IDs that have checklists (avoids N*M scan)
    checklist_achievement_ids =
      Store.list(:achievement_checklists)
      |> Enum.map(fn c -> c.achievementId end)
      |> MapSet.new()

    # Index all achievements
    achievements = Store.list(:achievements)

    indexed_count =
      achievements
      |> Enum.map(&index_achievement(&1, checklist_achievement_ids))
      |> Enum.count(& &1)

    Logger.debug("Achievement index built: #{indexed_count} achievements indexed")

    :ok
  end

  @doc """
  Lookup achievements matching an event.

  Returns a list of achievement definition maps that could be triggered
  by the given event type and target.

  ## Examples

      iex> AchievementIndex.lookup(:kill, 2790)
      [%{id: 123, type: :kill, ...}, ...]

      iex> AchievementIndex.lookup(:quest_complete, 14069)
      [%{id: 456, type: :quest_complete, ...}]

  """
  @spec lookup(atom(), term()) :: [map()]
  def lookup(event_type, target) do
    # Get specific target matches
    specific =
      :ets.lookup(@table, {event_type, target})
      |> Enum.map(fn {_key, def} -> def end)

    # Get "any" target matches (for counter achievements)
    any =
      :ets.lookup(@table, {event_type, :any})
      |> Enum.map(fn {_key, def} -> def end)

    specific ++ any
  end

  @doc """
  Lookup achievements by zone.

  Returns achievements that are zone-specific regardless of event type.
  """
  @spec lookup_by_zone(non_neg_integer()) :: [map()]
  def lookup_by_zone(zone_id) do
    :ets.lookup(@table, {:zone, zone_id})
    |> Enum.map(fn {_key, def} -> def end)
  end

  @doc """
  Get the count of indexed achievements.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table, :size)
  end

  @doc """
  Get all unique event types in the index.
  """
  @spec event_types() :: [atom()]
  def event_types do
    :ets.tab2list(@table)
    |> Enum.map(fn {{event_type, _target}, _def} -> event_type end)
    |> Enum.uniq()
  end

  # Index a single achievement into the ETS table
  # Returns true if indexed, false if skipped (unknown type)
  defp index_achievement(achievement, checklist_set) do
    type_id = Map.get(achievement, :achievementTypeId)
    event_type = AchievementTypes.event_type(type_id)

    if event_type do
      def_map = build_def_map(achievement, event_type, type_id, checklist_set)

      if AchievementTypes.uses_object_id?(type_id) and get_object_id(achievement) > 0 do
        # Index by specific object
        :ets.insert(@table, {{event_type, get_object_id(achievement)}, def_map})
      else
        # Index as "any" for counter achievements
        :ets.insert(@table, {{event_type, :any}, def_map})
      end

      # Also index by zone if present (for zone-specific achievements)
      zone_id = get_zone_id(achievement)

      if zone_id > 0 do
        :ets.insert(@table, {{:zone, zone_id}, def_map})
      end

      true
    else
      false
    end
  end

  defp build_def_map(achievement, event_type, type_id, checklist_set) do
    achievement_id = Map.get(achievement, :id) || Map.get(achievement, :ID)

    %{
      id: achievement_id,
      type: event_type,
      type_id: type_id,
      object_id: get_object_id(achievement),
      target: get_value(achievement),
      zone_id: get_zone_id(achievement),
      title_id: Map.get(achievement, :characterTitleId, 0),
      points: AchievementTypes.points_for_enum(Map.get(achievement, :achievementPointEnum, 0)),
      has_checklist: MapSet.member?(checklist_set, achievement_id)
    }
  end

  # Helper to get object ID with fallback for different key formats
  defp get_object_id(achievement) do
    Map.get(achievement, :objectId) ||
      Map.get(achievement, :objectId00) ||
      0
  end

  # Helper to get value/target with fallback
  defp get_value(achievement) do
    Map.get(achievement, :value) ||
      Map.get(achievement, :objectIdCount) ||
      1
  end

  # Helper to get zone ID with fallback
  defp get_zone_id(achievement) do
    Map.get(achievement, :worldZoneId, 0)
  end
end
