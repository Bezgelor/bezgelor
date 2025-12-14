defmodule BezgelorPortal.GameData do
  @moduledoc """
  Helper functions for WildStar game data lookups.

  Provides human-readable names for races, classes, factions, and other
  game constants used in the portal UI.
  """

  # Race IDs (from NexusForever.Game.Static.Entity.Race)
  @races %{
    1 => %{name: "Human", faction: :exile, icon: "human"},
    2 => %{name: "Cassian", faction: :dominion, icon: "cassian"},
    3 => %{name: "Granok", faction: :exile, icon: "granok"},
    4 => %{name: "Aurin", faction: :exile, icon: "aurin"},
    5 => %{name: "Draken", faction: :dominion, icon: "draken"},
    12 => %{name: "Mechari", faction: :dominion, icon: "mechari"},
    13 => %{name: "Chua", faction: :dominion, icon: "chua"},
    16 => %{name: "Mordesh", faction: :exile, icon: "mordesh"}
  }

  # Class IDs (from NexusForever.Game.Static.Entity.Class)
  @classes %{
    1 => %{name: "Warrior", icon: "warrior", color: "#C69B6D"},
    2 => %{name: "Engineer", icon: "engineer", color: "#F1C40F"},
    3 => %{name: "Esper", icon: "esper", color: "#9B59B6"},
    4 => %{name: "Medic", icon: "medic", color: "#3498DB"},
    5 => %{name: "Stalker", icon: "stalker", color: "#2ECC71"},
    7 => %{name: "Spellslinger", icon: "spellslinger", color: "#E74C3C"}
  }

  # Faction IDs
  @factions %{
    166 => %{name: "Exile", color: "#3498DB", icon: "exile"},
    167 => %{name: "Dominion", color: "#E74C3C", icon: "dominion"}
  }

  # Path IDs
  @paths %{
    0 => %{name: "Soldier", icon: "soldier"},
    1 => %{name: "Settler", icon: "settler"},
    2 => %{name: "Scientist", icon: "scientist"},
    3 => %{name: "Explorer", icon: "explorer"}
  }

  @doc """
  Get race information by ID.
  """
  @spec get_race(integer()) :: map()
  def get_race(id), do: Map.get(@races, id, %{name: "Unknown", faction: :unknown, icon: "unknown"})

  @doc """
  Get race name by ID.
  """
  @spec race_name(integer()) :: String.t()
  def race_name(id), do: get_race(id).name

  @doc """
  Get class information by ID.
  """
  @spec get_class(integer()) :: map()
  def get_class(id), do: Map.get(@classes, id, %{name: "Unknown", icon: "unknown", color: "#666"})

  @doc """
  Get class name by ID.
  """
  @spec class_name(integer()) :: String.t()
  def class_name(id), do: get_class(id).name

  @doc """
  Get class color by ID.
  """
  @spec class_color(integer()) :: String.t()
  def class_color(id), do: get_class(id).color

  @doc """
  Get faction information by ID.
  """
  @spec get_faction(integer()) :: map()
  def get_faction(id), do: Map.get(@factions, id, %{name: "Unknown", color: "#666", icon: "unknown"})

  @doc """
  Get faction name by ID.
  """
  @spec faction_name(integer()) :: String.t()
  def faction_name(id), do: get_faction(id).name

  @doc """
  Get faction color by ID.
  """
  @spec faction_color(integer()) :: String.t()
  def faction_color(id), do: get_faction(id).color

  @doc """
  Get path information by ID.
  """
  @spec get_path(integer()) :: map()
  def get_path(id), do: Map.get(@paths, id, %{name: "Unknown", icon: "unknown"})

  @doc """
  Get path name by ID.
  """
  @spec path_name(integer()) :: String.t()
  def path_name(id), do: get_path(id).name

  @doc """
  Format play time from seconds to human-readable string.
  """
  @spec format_play_time(integer()) :: String.t()
  def format_play_time(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      hours >= 24 ->
        days = div(hours, 24)
        remaining_hours = rem(hours, 24)
        "#{days}d #{remaining_hours}h"

      hours >= 1 ->
        "#{hours}h #{minutes}m"

      true ->
        "#{minutes}m"
    end
  end

  def format_play_time(_), do: "0m"

  @doc """
  Format a DateTime to relative time (e.g., "2 hours ago").
  """
  @spec format_relative_time(DateTime.t() | nil) :: String.t()
  def format_relative_time(nil), do: "Never"

  def format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      diff < 2_592_000 -> "#{div(diff, 604_800)} weeks ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  @doc """
  Get all races.
  """
  @spec all_races() :: map()
  def all_races, do: @races

  @doc """
  Get all classes.
  """
  @spec all_classes() :: map()
  def all_classes, do: @classes

  @doc """
  Get all factions.
  """
  @spec all_factions() :: map()
  def all_factions, do: @factions

  @doc """
  Get all paths.
  """
  @spec all_paths() :: map()
  def all_paths, do: @paths

  @doc """
  Get zone name by ID, looking up from game data.
  """
  @spec zone_name(integer() | nil) :: String.t()
  def zone_name(nil), do: "Unknown"

  def zone_name(zone_id) do
    case BezgelorData.get_zone_with_name(zone_id) do
      {:ok, zone} -> zone.name || "Zone #{zone_id}"
      :error -> "Zone #{zone_id}"
    end
  end

  @doc """
  Get world name by ID. Since we don't have a world table with names,
  we use known world IDs or fall back to the ID.
  """
  @spec world_name(integer() | nil) :: String.t()
  def world_name(nil), do: "Unknown"

  def world_name(world_id) do
    # Known world IDs from WildStar (mapped from game data analysis)
    case world_id do
      22 -> "Eastern Continent"
      51 -> "Western Continent"
      426 -> "Arcterra"
      870 -> "Nexus"
      990 -> "Star-Comm Basin"
      1061 -> "Halon Ring"
      1068 -> "Farside"
      1181 -> "Blighthaven"
      1323 -> "The Defile"
      1333 -> "Northern Wastes"
      1387 -> "Levian Bay"
      1421 -> "Housing Skymap"
      1629 -> "Genetic Archives"
      3335 -> "Omnicore-1"
      _ -> "World #{world_id}"
    end
  end
end
