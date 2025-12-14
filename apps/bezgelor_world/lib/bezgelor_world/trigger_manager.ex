defmodule BezgelorWorld.TriggerManager do
  @moduledoc """
  Manages trigger volumes and detects when entities enter/exit them.

  ## Overview

  Trigger volumes are defined by world locations with a position and radius.
  When a player's position update moves them into a trigger, an event is fired.

  ## Usage

      # Load triggers for a zone
      triggers = TriggerManager.load_zone_triggers(zone_id)

      # Check for trigger entry on movement
      {entered, exited, new_active} = TriggerManager.check_triggers(
        triggers,
        old_position,
        new_position,
        active_triggers
      )

      # Fire events for entered triggers
      for trigger_id <- entered do
        EventDispatcher.dispatch_enter_area(session_data, trigger_id, zone_id)
      end
  """

  require Logger

  @type position :: {float(), float(), float()}
  @type trigger :: %{
          id: non_neg_integer(),
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: position(),
          radius: float()
        }

  # Default radius for triggers with radius <= 1.0
  @default_radius 3.0

  @doc """
  Load trigger volumes for a zone from world locations.
  """
  @spec load_zone_triggers(non_neg_integer()) :: [trigger()]
  def load_zone_triggers(zone_id) do
    BezgelorData.world_locations_for_zone(zone_id)
    |> Enum.map(&build_trigger/1)
  end

  @doc """
  Load trigger volumes for a world from world locations.
  """
  @spec load_world_triggers(non_neg_integer()) :: [trigger()]
  def load_world_triggers(world_id) do
    BezgelorData.world_locations_for_world(world_id)
    |> Enum.map(&build_trigger/1)
  end

  @doc """
  Build a trigger struct from world location data.
  """
  @spec build_trigger(map()) :: trigger()
  def build_trigger(world_location) do
    raw_radius = Map.get(world_location, "radius", 1.0)
    # Many world locations have radius 1.0 which is too small
    radius = if raw_radius <= 1.0, do: @default_radius, else: raw_radius

    %{
      id: Map.get(world_location, "ID", 0),
      world_id: Map.get(world_location, "worldId", 0),
      zone_id: Map.get(world_location, "worldZoneId", 0),
      position: {
        Map.get(world_location, "position0", 0.0),
        Map.get(world_location, "position1", 0.0),
        Map.get(world_location, "position2", 0.0)
      },
      radius: radius
    }
  end

  @doc """
  Check if a position is within a trigger's radius.
  """
  @spec in_trigger?(position(), trigger()) :: boolean()
  def in_trigger?({px, py, pz}, %{position: {tx, ty, tz}, radius: radius}) do
    dx = px - tx
    dy = py - ty
    dz = pz - tz
    distance_sq = dx * dx + dy * dy + dz * dz
    distance_sq <= radius * radius
  end

  @doc """
  Check which triggers a position update enters/exits.

  Returns `{entered_ids, exited_ids, new_active_set}`.
  """
  @spec check_triggers([trigger()], position(), position(), MapSet.t()) ::
          {[non_neg_integer()], [non_neg_integer()], MapSet.t()}
  def check_triggers(triggers, _old_position, new_position, active_triggers) do
    # Find all triggers the new position is inside
    current_triggers =
      triggers
      |> Enum.filter(&in_trigger?(new_position, &1))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Calculate entered and exited
    entered = MapSet.difference(current_triggers, active_triggers) |> MapSet.to_list()
    exited = MapSet.difference(active_triggers, current_triggers) |> MapSet.to_list()

    {entered, exited, current_triggers}
  end

  @doc """
  Get a specific trigger by ID from a list.
  """
  @spec get_trigger([trigger()], non_neg_integer()) :: trigger() | nil
  def get_trigger(triggers, id) do
    Enum.find(triggers, &(&1.id == id))
  end
end
