defmodule BezgelorWorld.Path.SessionPathManager do
  @dialyzer :no_match

  @moduledoc """
  Session-based path mission management for efficient in-memory tracking.

  ## Overview

  This module handles path mission operations using session_data stored in the
  Connection process, mirroring the pattern from SessionQuestManager.

  ## Mission Types by Path

  ### Soldier (pathTypeEnum=0) - 279 missions
  | Type | Name | Count | Event |
  |------|------|-------|-------|
  | 0 | Holdout | 98 | :holdout_wave, :holdout_complete |
  | 4 | Assassination | 71 | :kill |
  | 5 | SWAT | 33 | :kill, :area_clear |
  | 6 | Demolition | 26 | :destroy_object |
  | 7 | Rescue | 51 | :escort_complete, :npc_saved |

  ### Settler (pathTypeEnum=1) - 246 missions
  | Type | Name | Count | Event |
  |------|------|-------|-------|
  | 19 | Infrastructure | 68 | :build, :repair |
  | 21 | Civil Service | 42 | :help_npc, :interact |
  | 25 | Cache | 47 | :loot, :discover |
  | 26 | Project | 44 | :build_progress |
  | 27 | Depot | 45 | :depot_placed |

  ### Scientist (pathTypeEnum=2) - 275 missions
  | Type | Name | Count | Event |
  |------|------|-------|-------|
  | 2 | Scan | 163 | :scan |
  | 14 | Datacube | 57 | :datacube |
  | 20 | Field Study | 9 | :observe |
  | 22 | Specimen | 13 | :collect_specimen |
  | 23 | Biology | 16 | :scan, :analyze |
  | 24 | Archaeology | 17 | :discover, :excavate |

  ### Explorer (pathTypeEnum=3) - 264 missions
  | Type | Name | Count | Event |
  |------|------|-------|-------|
  | 3 | Cartography | 23 | :discover_area |
  | 12 | Surveillance | 36 | :observe, :photograph |
  | 13 | Operations | 56 | :interact, :complete_objective |
  | 15 | Vista | 82 | :reach_location |
  | 16 | Tracking | 20 | :follow_trail, :reach_location |
  | 17 | Scavenger Hunt | 22 | :loot, :discover |
  | 18 | Stake Claim | 25 | :claim_territory |

  ## Usage

      # In Connection.handle_info (via EventDispatcher)
      def handle_info({:game_event, event_type, event_data}, state) do
        {session_data, packets} = EventDispatcher.process_game_event(
          state.session_data,
          event_type,
          event_data
        )
        # Send packets and update state
      end
  """

  alias BezgelorData.Store
  alias BezgelorProtocol.Packets.World.{ServerPathMissionUpdate, ServerPathMissionComplete}

  require Logger

  # ============================================================================
  # Mission Type Constants (26 types from path_missions data)
  # ============================================================================

  # Soldier mission types (pathTypeEnum=0)
  @type_holdout 0           # 98 missions - Defend against waves
  @type_assassination 4     # 71 missions - Kill specific target
  @type_swat 5              # 33 missions - Clear area of enemies
  @type_demolition 6        # 26 missions - Destroy objects
  @type_rescue 7            # 51 missions - Save/escort NPCs

  # Settler mission types (pathTypeEnum=1)
  @type_infrastructure 19   # 68 missions - Build/repair structures
  @type_civil_service 21    # 42 missions - Help NPCs
  @type_cache 25            # 47 missions - Find hidden caches
  @type_project 26          # 44 missions - Major building projects
  @type_depot 27            # 45 missions - Place buff depots

  # Scientist mission types (pathTypeEnum=2)
  @type_scan 2              # 163 missions - Scan creatures/objects
  @type_datacube 14         # 57 missions - Find lore datacubes
  @type_field_study 20      # 9 missions - Observe creature behavior
  @type_specimen 22         # 13 missions - Collect specimens
  @type_biology 23          # 16 missions - Analyze creatures
  @type_archaeology 24      # 17 missions - Discover artifacts

  # Explorer mission types (pathTypeEnum=3)
  @type_cartography 3       # 23 missions - Map unexplored areas
  @type_surveillance 12     # 36 missions - Observe/photograph
  @type_operations 13       # 56 missions - Complete objectives
  @type_vista 15            # 82 missions - Reach locations (jumping puzzles)
  @type_tracking 16         # 20 missions - Follow trails
  @type_scavenger_hunt 17   # 22 missions - Find hidden items
  @type_stake_claim 18      # 25 missions - Claim territory

  # Path type constants (used for documentation, suppress unused warning)
  # Soldier=0, Settler=1, Scientist=2, Explorer=3

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Process a game event and update any matching path mission objectives.

  Returns `{updated_session_data, packets_to_send}`.
  """
  @spec process_game_event(map(), atom(), map()) :: {map(), [{atom(), binary()}]}
  def process_game_event(session_data, event_type, event_data) do
    active_missions = session_data[:active_path_missions] || %{}

    {updated_missions, packets} =
      Enum.reduce(active_missions, {%{}, []}, fn {mission_id, mission}, {missions_acc, packets_acc} ->
        {updated_mission, mission_packets} = process_mission_event(mission, event_type, event_data)
        {Map.put(missions_acc, mission_id, updated_mission), packets_acc ++ mission_packets}
      end)

    # Check if any missions became completable
    {updated_missions, completion_packets} = check_all_completable(updated_missions, session_data)

    updated_session = Map.put(session_data, :active_path_missions, updated_missions)

    # Mark session as dirty if we updated anything
    updated_session =
      if packets != [] or completion_packets != [] do
        Map.put(updated_session, :path_dirty, true)
      else
        updated_session
      end

    {updated_session, packets ++ completion_packets}
  end

  @doc """
  Initialize path missions for a zone entry.

  Loads available missions for the player's path in the given zone.
  """
  @spec initialize_zone_missions(map(), integer(), integer(), integer(), integer()) :: {map(), [{atom(), binary()}]}
  def initialize_zone_missions(session_data, _character_id, path_type, world_id, zone_id) do
    # Get completed mission IDs
    completed_ids = session_data[:completed_path_mission_ids] || MapSet.new()
    faction = session_data[:faction] || 0

    # Find missions for this zone and path
    available_missions =
      get_zone_missions(path_type, world_id, zone_id)
      |> Enum.reject(fn m -> MapSet.member?(completed_ids, m["ID"]) end)
      |> Enum.filter(fn m -> faction_matches?(m["pathMissionFactionEnum"], faction) end)
      |> Enum.filter(fn m -> prerequisite_met?(m["prerequisiteId"], completed_ids) end)

    # Add to active missions
    active_missions = session_data[:active_path_missions] || %{}

    {new_missions, packets} =
      Enum.reduce(available_missions, {active_missions, []}, fn mission_data, {acc, pkts} ->
        mission_id = mission_data["ID"]

        if Map.has_key?(acc, mission_id) do
          {acc, pkts}
        else
          mission_state = build_mission_state(mission_data)
          packet = build_mission_update_packet(mission_id, mission_state)
          {Map.put(acc, mission_id, mission_state), pkts ++ [packet]}
        end
      end)

    updated_session = Map.put(session_data, :active_path_missions, new_missions)

    Logger.debug("Initialized #{length(packets)} path missions for zone #{zone_id}, path #{path_name(path_type)}")

    {updated_session, packets}
  end

  @doc """
  Activate a specific mission (e.g., when approaching location).
  """
  @spec activate_mission(map(), integer(), integer()) :: {map(), [{atom(), binary()}]} | {:error, term()}
  def activate_mission(session_data, _character_id, mission_id) do
    case Store.get_path_mission(mission_id) do
      {:ok, mission_data} ->
        active_missions = session_data[:active_path_missions] || %{}

        if Map.has_key?(active_missions, mission_id) do
          {session_data, []}
        else
          mission_state = build_mission_state(mission_data)
          packet = build_mission_update_packet(mission_id, mission_state)

          updated_missions = Map.put(active_missions, mission_id, mission_state)
          updated_session = Map.put(session_data, :active_path_missions, updated_missions)

          {updated_session, [packet]}
        end

      :error ->
        {:error, :mission_not_found}
    end
  end

  @doc """
  Complete a mission and award rewards.
  """
  @spec complete_mission(map(), integer(), integer()) :: {map(), [{atom(), binary()}]}
  def complete_mission(session_data, _character_id, mission_id) do
    active_missions = session_data[:active_path_missions] || %{}

    case Map.get(active_missions, mission_id) do
      nil ->
        {session_data, []}

      _mission ->
        # Get XP reward from mission data
        xp_reward = get_mission_xp_reward(mission_id)

        # Build completion packet
        packet = build_completion_packet(mission_id, xp_reward)

        # Move to completed
        completed_ids = session_data[:completed_path_mission_ids] || MapSet.new()
        updated_completed = MapSet.put(completed_ids, mission_id)
        updated_missions = Map.delete(active_missions, mission_id)

        updated_session =
          session_data
          |> Map.put(:active_path_missions, updated_missions)
          |> Map.put(:completed_path_mission_ids, updated_completed)
          |> Map.put(:pending_path_xp, (session_data[:pending_path_xp] || 0) + xp_reward)

        Logger.info("Path mission #{mission_id} completed, +#{xp_reward} path XP")

        {updated_session, [packet]}
    end
  end

  @doc """
  Abandon a mission (remove from active without completing).
  """
  @spec abandon_mission(map(), integer()) :: map()
  def abandon_mission(session_data, mission_id) do
    active_missions = session_data[:active_path_missions] || %{}
    updated_missions = Map.delete(active_missions, mission_id)
    Map.put(session_data, :active_path_missions, updated_missions)
  end

  @doc """
  Get all active missions for a specific path type.
  """
  @spec get_active_by_path(map(), integer()) :: [map()]
  def get_active_by_path(session_data, path_type) do
    active_missions = session_data[:active_path_missions] || %{}

    active_missions
    |> Map.values()
    |> Enum.filter(fn m -> m.path_type == path_type end)
  end

  # ============================================================================
  # Event Processing
  # ============================================================================

  defp process_mission_event(mission, event_type, event_data) do
    if mission.state != :active do
      {mission, []}
    else
      process_objectives(mission, event_type, event_data)
    end
  end

  defp process_objectives(mission, event_type, event_data) do
    mission_type = mission.mission_type

    if matches_event?(mission_type, event_type, event_data, mission) do
      # Increment progress
      current = mission.progress["count"] || 0
      target = mission.progress["target"] || 1
      new_count = min(current + 1, target)

      new_progress = Map.put(mission.progress, "count", new_count)
      updated_mission = %{mission | progress: new_progress, dirty: true}

      packet = build_mission_update_packet(mission.mission_id, updated_mission)

      {updated_mission, [packet]}
    else
      {mission, []}
    end
  end

  # ============================================================================
  # Event Matching (26 mission types)
  # ============================================================================

  # Soldier: Holdout - defend against waves
  defp matches_event?(@type_holdout, :holdout_wave, %{holdout_id: holdout_id}, mission) do
    mission.object_id == holdout_id
  end

  defp matches_event?(@type_holdout, :holdout_complete, %{holdout_id: holdout_id}, mission) do
    mission.object_id == holdout_id
  end

  # Soldier: Assassination - kill specific target
  defp matches_event?(@type_assassination, :kill, %{creature_id: creature_id}, mission) do
    mission.object_id == creature_id
  end

  # Soldier: SWAT - clear area of enemies
  defp matches_event?(@type_swat, :kill, %{creature_id: creature_id, zone_id: zone_id}, mission) do
    # TODO: Implement proper area/creature checks when mission data is available
    _in_area = in_mission_area?(mission, zone_id)
    _in_list = creature_in_target_list?(mission, creature_id)
    true
  end

  defp matches_event?(@type_swat, :area_clear, %{area_id: area_id}, mission) do
    mission.object_id == area_id
  end

  # Soldier: Demolition - destroy objects
  defp matches_event?(@type_demolition, :destroy_object, %{object_id: object_id}, mission) do
    mission.object_id == object_id
  end

  # Soldier: Rescue - save/escort NPCs
  defp matches_event?(@type_rescue, :escort_complete, %{npc_id: npc_id}, mission) do
    mission.object_id == npc_id
  end

  defp matches_event?(@type_rescue, :npc_saved, %{npc_id: npc_id}, mission) do
    mission.object_id == npc_id
  end

  # Settler: Infrastructure - build/repair
  defp matches_event?(@type_infrastructure, :build, %{structure_id: structure_id}, mission) do
    mission.object_id == structure_id
  end

  defp matches_event?(@type_infrastructure, :repair, %{structure_id: structure_id}, mission) do
    mission.object_id == structure_id
  end

  # Settler: Civil Service - help NPCs
  defp matches_event?(@type_civil_service, :help_npc, %{npc_id: npc_id}, mission) do
    mission.object_id == npc_id
  end

  defp matches_event?(@type_civil_service, :interact, %{object_id: object_id}, mission) do
    mission.object_id == object_id
  end

  # Settler: Cache - find hidden caches
  defp matches_event?(@type_cache, :loot, %{cache_id: cache_id}, mission) do
    mission.object_id == cache_id
  end

  defp matches_event?(@type_cache, :discover, %{cache_id: cache_id}, mission) do
    mission.object_id == cache_id
  end

  # Settler: Project - major building
  defp matches_event?(@type_project, :build_progress, %{project_id: project_id}, mission) do
    mission.object_id == project_id
  end

  # Settler: Depot - place depots
  defp matches_event?(@type_depot, :depot_placed, %{depot_type: depot_type}, mission) do
    mission.object_id == depot_type or mission.object_id == 0
  end

  # Scientist: Scan - scan creatures/objects
  defp matches_event?(@type_scan, :scan, %{target_id: target_id}, mission) do
    mission.object_id == target_id or mission.object_id == 0
  end

  # Scientist: Datacube - find lore
  defp matches_event?(@type_datacube, :datacube, %{datacube_id: datacube_id}, mission) do
    mission.object_id == datacube_id
  end

  # Scientist: Field Study - observe behavior
  defp matches_event?(@type_field_study, :observe, %{creature_id: creature_id}, mission) do
    mission.object_id == creature_id
  end

  # Scientist: Specimen - collect samples
  defp matches_event?(@type_specimen, :collect_specimen, %{specimen_id: specimen_id}, mission) do
    mission.object_id == specimen_id
  end

  defp matches_event?(@type_specimen, :loot, %{item_id: item_id}, mission) do
    # Specimens can drop as items
    mission.object_id == item_id
  end

  # Scientist: Biology - analyze creatures
  defp matches_event?(@type_biology, :scan, %{creature_id: creature_id}, mission) do
    mission.object_id == creature_id
  end

  defp matches_event?(@type_biology, :analyze, %{creature_id: creature_id}, mission) do
    mission.object_id == creature_id
  end

  # Scientist: Archaeology - discover artifacts
  defp matches_event?(@type_archaeology, :discover, %{artifact_id: artifact_id}, mission) do
    mission.object_id == artifact_id
  end

  defp matches_event?(@type_archaeology, :excavate, %{site_id: site_id}, mission) do
    mission.object_id == site_id
  end

  # Explorer: Cartography - map areas
  defp matches_event?(@type_cartography, :discover_area, %{area_id: area_id}, mission) do
    mission.object_id == area_id
  end

  # Explorer: Surveillance - observe/photograph
  defp matches_event?(@type_surveillance, :observe, %{target_id: target_id}, mission) do
    mission.object_id == target_id
  end

  defp matches_event?(@type_surveillance, :photograph, %{target_id: target_id}, mission) do
    mission.object_id == target_id
  end

  # Explorer: Operations - complete objectives
  defp matches_event?(@type_operations, :interact, %{object_id: object_id}, mission) do
    mission.object_id == object_id
  end

  defp matches_event?(@type_operations, :complete_objective, %{objective_id: objective_id}, mission) do
    mission.object_id == objective_id
  end

  # Explorer: Vista - reach locations (jumping puzzles)
  defp matches_event?(@type_vista, :reach_location, %{location_id: location_id}, mission) do
    location_id in mission.location_ids
  end

  defp matches_event?(@type_vista, :enter_area, %{area_id: area_id}, mission) do
    area_id in mission.location_ids
  end

  # Explorer: Tracking - follow trails
  defp matches_event?(@type_tracking, :follow_trail, %{trail_id: trail_id}, mission) do
    mission.object_id == trail_id
  end

  defp matches_event?(@type_tracking, :reach_location, %{location_id: location_id}, mission) do
    location_id in mission.location_ids
  end

  # Explorer: Scavenger Hunt - find items
  defp matches_event?(@type_scavenger_hunt, :loot, %{item_id: item_id}, mission) do
    mission.object_id == item_id
  end

  defp matches_event?(@type_scavenger_hunt, :discover, %{object_id: object_id}, mission) do
    mission.object_id == object_id
  end

  # Explorer: Stake Claim - claim territory
  defp matches_event?(@type_stake_claim, :claim_territory, %{territory_id: territory_id}, mission) do
    mission.object_id == territory_id
  end

  # Default: no match
  defp matches_event?(_, _, _, _), do: false

  # ============================================================================
  # Completion Checking
  # ============================================================================

  defp check_all_completable(missions, _session_data) do
    Enum.reduce(missions, {%{}, []}, fn {mission_id, mission}, {acc, packets} ->
      if mission_completable?(mission) do
        # Note: updated_mission not used since auto-completing removes mission
        _updated_mission = %{mission | state: :completable}

        # Auto-complete path missions (they don't require turn-in)
        {acc, packets ++ [build_completion_packet(mission_id, get_mission_xp_reward(mission_id))]}
      else
        {Map.put(acc, mission_id, mission), packets}
      end
    end)
  end

  defp mission_completable?(mission) do
    mission.state == :active and
      (mission.progress["count"] || 0) >= (mission.progress["target"] || 1)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp get_zone_missions(path_type, world_id, zone_id) do
    # Use indexed lookup for O(1) performance
    Store.get_zone_path_missions(world_id, zone_id, path_type)
  end

  defp faction_matches?(0, _player_faction), do: true  # Both factions
  defp faction_matches?(mission_faction, player_faction), do: mission_faction == player_faction

  defp prerequisite_met?(0, _completed_ids), do: true
  defp prerequisite_met?(nil, _completed_ids), do: true
  defp prerequisite_met?(prereq_id, completed_ids), do: MapSet.member?(completed_ids, prereq_id)

  defp build_mission_state(mission_data) do
    %{
      mission_id: mission_data["ID"],
      mission_type: mission_data["pathMissionTypeEnum"],
      path_type: mission_data["pathTypeEnum"],
      object_id: mission_data["objectId"],
      location_ids: extract_location_ids(mission_data),
      state: :active,
      progress: %{"count" => 0, "target" => get_target_count(mission_data)},
      dirty: false
    }
  end

  defp extract_location_ids(mission_data) do
    [
      mission_data["worldLocation2Id00"],
      mission_data["worldLocation2Id01"],
      mission_data["worldLocation2Id02"],
      mission_data["worldLocation2Id03"]
    ]
    |> Enum.reject(&(&1 == 0 or is_nil(&1)))
  end

  defp get_target_count(_mission_data) do
    # Default target, can be enhanced to look up from additional data
    1
  end

  defp get_mission_xp_reward(mission_id) do
    # Base XP reward - can be enhanced with path_rewards.json lookup
    case Store.get_path_mission(mission_id) do
      {:ok, mission} ->
        # Different mission types have different base XP
        case mission["pathMissionTypeEnum"] do
          @type_holdout -> 200
          @type_vista -> 150
          @type_datacube -> 100
          @type_scan -> 75
          _ -> 100
        end

      :error ->
        100
    end
  end

  defp in_mission_area?(_mission, _zone_id), do: true  # Simplified for now

  defp creature_in_target_list?(_mission, _creature_id), do: true  # Simplified for now

  defp build_mission_update_packet(mission_id, mission_state) do
    {:server_path_mission_update, %ServerPathMissionUpdate{
      mission_id: mission_id,
      progress: mission_state.progress
    }}
  end

  defp build_completion_packet(mission_id, xp_reward) do
    {:server_path_mission_complete, %ServerPathMissionComplete{
      mission_id: mission_id,
      xp_reward: xp_reward
    }}
  end

  defp path_name(0), do: "Soldier"
  defp path_name(1), do: "Settler"
  defp path_name(2), do: "Scientist"
  defp path_name(3), do: "Explorer"
  defp path_name(_), do: "Unknown"
end
