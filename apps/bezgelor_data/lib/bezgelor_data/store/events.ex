defmodule BezgelorData.Store.Events do
  @moduledoc """
  Event and world boss-related data queries for the Store.

  Provides functions for querying public events, world bosses,
  event spawn points, and event loot tables.

  ## Public Events

  Public events are zone-wide activities that players can participate in
  for rewards. They have schedules, spawn points, and tiered loot.

  ## World Bosses

  World bosses are powerful creatures that spawn on schedules and require
  group coordination to defeat.

  ## Loot Tables

  Event loot tables define tiered rewards (gold, silver, bronze, participation)
  based on player contribution.
  """

  alias BezgelorData.Store.{Core, Index}

  # Public Event queries

  @doc """
  Get a public event definition by ID.
  """
  @spec get_public_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_public_event(id), do: Core.get(:public_events, id)

  @doc """
  Get all public events for a zone.

  Uses secondary index for O(1) lookup instead of scanning all events.
  """
  @spec get_zone_public_events(non_neg_integer()) :: [map()]
  def get_zone_public_events(zone_id) do
    ids = Index.lookup_index(:events_by_zone, zone_id)
    Index.fetch_by_ids(:public_events, ids)
  end

  # World Boss queries

  @doc """
  Get a world boss definition by ID.
  """
  @spec get_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_boss(id), do: Core.get(:world_bosses, id)

  @doc """
  Get all world bosses for a zone.

  Uses secondary index for O(1) lookup instead of scanning all bosses.
  """
  @spec get_zone_world_bosses(non_neg_integer()) :: [map()]
  def get_zone_world_bosses(zone_id) do
    ids = Index.lookup_index(:world_bosses_by_zone, zone_id)
    Index.fetch_by_ids(:world_bosses, ids)
  end

  # Event Spawn Points

  @doc """
  Get spawn points for a zone.
  """
  @spec get_event_spawn_points(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_spawn_points(zone_id), do: Core.get(:event_spawn_points, zone_id)

  @doc """
  Get specific spawn point group.
  """
  @spec get_spawn_point_group(non_neg_integer(), String.t()) :: [map()]
  def get_spawn_point_group(zone_id, group_name) do
    case get_event_spawn_points(zone_id) do
      {:ok, data} -> Map.get(data.spawn_point_groups, group_name, [])
      :error -> []
    end
  end

  # Event Loot Tables

  @doc """
  Get an event loot table by ID.
  """
  @spec get_event_loot_table(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_loot_table(id), do: Core.get(:event_loot_tables, id)

  @doc """
  Get loot table for an event.
  """
  @spec get_loot_table_for_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_event(event_id) do
    case Enum.find(Core.list(:event_loot_tables), fn lt -> lt.event_id == event_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get loot table for a world boss.
  """
  @spec get_loot_table_for_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_world_boss(boss_id) do
    case Enum.find(Core.list(:event_loot_tables), fn lt -> lt[:world_boss_id] == boss_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get tier drops from a loot table.
  """
  @spec get_tier_drops(non_neg_integer(), atom()) :: [map()]
  def get_tier_drops(loot_table_id, tier)
      when tier in [:gold, :silver, :bronze, :participation] do
    case get_event_loot_table(loot_table_id) do
      {:ok, loot_table} ->
        tier_key = Atom.to_string(tier)
        Map.get(loot_table.tier_drops, String.to_atom(tier_key), [])

      :error ->
        []
    end
  end
end
