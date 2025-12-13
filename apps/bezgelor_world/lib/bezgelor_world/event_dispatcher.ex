defmodule BezgelorWorld.EventDispatcher do
  @moduledoc """
  Unified event dispatcher for routing game events to quest and path mission systems.

  ## Overview

  This module centralizes game event processing, ensuring both quest objectives
  and path missions receive relevant events without duplicate code in handlers.

  ## Event Types

  | Category | Events | Quest Types | Path Types |
  |----------|--------|-------------|------------|
  | Combat | :kill, :kill_type | 2 (Kill), 39 (KillType) | Assassination, SWAT, Biology |
  | Loot | :loot, :loot_type | 3 (Collect), 22 (CollectType) | Cache, Specimen, Scavenger |
  | Interaction | :interact, :activate | 0 (Talk), 5 (Interact) | Infrastructure, Civil Service, Operations |
  | Location | :reach_location, :enter_area, :discover_area | 4 (Location), 18 (Zone) | Vista, Tracking, Cartography |
  | Scanning | :scan, :analyze | 40 (Scan) | Scan, Biology, Archaeology |
  | Communication | :talk_to, :communicate | 0 (Talk), 6 (TalkToType) | - |
  | Exploration | :discover, :datacube | 17 (Explore) | Datacube, Cache |
  | Construction | :build, :repair, :depot_placed | - | Infrastructure, Project, Depot |
  | Special | :holdout_wave, :escort_complete, :npc_saved | - | Holdout, Rescue |

  ## Usage

      # In Connection process
      def handle_info({:game_event, event_type, event_data}, state) do
        {updated_session, packets} = EventDispatcher.dispatch(
          state.session_data,
          event_type,
          event_data
        )
        # Send packets and update state
        send_packets(packets, state)
        {:noreply, %{state | session_data: updated_session}}
      end

      # In combat handler after kill
      EventDispatcher.dispatch(session_data, :kill, %{
        creature_id: creature_id,
        creature_type: creature_type,
        zone_id: zone_id
      })
  """

  alias BezgelorWorld.Quest.SessionQuestManager
  alias BezgelorWorld.Path.SessionPathManager

  require Logger

  @type event_type :: atom()
  @type event_data :: map()
  @type session_data :: map()
  @type packet :: {atom(), struct()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Dispatch a game event to all relevant subsystems.

  Returns `{updated_session_data, all_packets}`.
  """
  @spec dispatch(session_data(), event_type(), event_data()) :: {session_data(), [packet()]}
  def dispatch(session_data, event_type, event_data) do
    # Process quest objectives
    {session_after_quests, quest_packets} =
      SessionQuestManager.process_game_event(session_data, event_type, event_data)

    # Process path missions
    {session_after_paths, path_packets} =
      SessionPathManager.process_game_event(session_after_quests, event_type, event_data)

    # Log if any progress was made
    if quest_packets != [] or path_packets != [] do
      Logger.debug(
        "Event #{event_type} generated #{length(quest_packets)} quest + #{length(path_packets)} path packets"
      )
    end

    {session_after_paths, quest_packets ++ path_packets}
  end

  @doc """
  Dispatch a kill event with creature metadata.

  This is the most common event type and has a dedicated helper.
  """
  @spec dispatch_kill(session_data(), integer(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_kill(session_data, creature_id, creature_type, zone_id) do
    dispatch(session_data, :kill, %{
      creature_id: creature_id,
      creature_type: creature_type,
      zone_id: zone_id
    })
  end

  @doc """
  Dispatch a loot event when a player receives an item.
  """
  @spec dispatch_loot(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_loot(session_data, item_id, quantity \\ 1) do
    dispatch(session_data, :loot, %{
      item_id: item_id,
      quantity: quantity
    })
  end

  @doc """
  Dispatch an interaction event when a player interacts with an object or NPC.
  """
  @spec dispatch_interact(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_interact(session_data, target_id, target_type) do
    dispatch(session_data, :interact, %{
      object_id: target_id,
      target_type: target_type
    })
  end

  @doc """
  Dispatch a location reached event (for exploration objectives).
  """
  @spec dispatch_reach_location(session_data(), integer(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_reach_location(session_data, location_id, zone_id, world_id) do
    dispatch(session_data, :reach_location, %{
      location_id: location_id,
      zone_id: zone_id,
      world_id: world_id
    })
  end

  @doc """
  Dispatch a scan event when scientist scans a target.
  """
  @spec dispatch_scan(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_scan(session_data, target_id, target_type) do
    dispatch(session_data, :scan, %{
      target_id: target_id,
      target_type: target_type
    })
  end

  @doc """
  Dispatch a datacube discovery event.
  """
  @spec dispatch_datacube(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_datacube(session_data, datacube_id) do
    dispatch(session_data, :datacube, %{datacube_id: datacube_id})
  end

  @doc """
  Dispatch an area entry event (for zone-based triggers).
  """
  @spec dispatch_enter_area(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_enter_area(session_data, area_id, zone_id) do
    dispatch(session_data, :enter_area, %{
      area_id: area_id,
      zone_id: zone_id
    })
  end

  @doc """
  Dispatch an area discovery event (for Explorer cartography).
  """
  @spec dispatch_discover_area(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_discover_area(session_data, area_id) do
    dispatch(session_data, :discover_area, %{area_id: area_id})
  end

  @doc """
  Dispatch a talk/communicate event with an NPC.
  """
  @spec dispatch_talk(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_talk(session_data, npc_id, creature_type) do
    dispatch(session_data, :talk_to, %{
      npc_id: npc_id,
      creature_type: creature_type
    })
  end

  # ============================================================================
  # Settler-Specific Events
  # ============================================================================

  @doc """
  Dispatch a build event when settler constructs something.
  """
  @spec dispatch_build(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_build(session_data, structure_id, progress \\ 1) do
    dispatch(session_data, :build, %{
      structure_id: structure_id,
      progress: progress
    })
  end

  @doc """
  Dispatch a depot placed event.
  """
  @spec dispatch_depot_placed(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_depot_placed(session_data, depot_type) do
    dispatch(session_data, :depot_placed, %{depot_type: depot_type})
  end

  # ============================================================================
  # Soldier-Specific Events
  # ============================================================================

  @doc """
  Dispatch a holdout wave event.
  """
  @spec dispatch_holdout_wave(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def dispatch_holdout_wave(session_data, holdout_id, wave_number) do
    dispatch(session_data, :holdout_wave, %{
      holdout_id: holdout_id,
      wave: wave_number
    })
  end

  @doc """
  Dispatch a holdout complete event.
  """
  @spec dispatch_holdout_complete(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_holdout_complete(session_data, holdout_id) do
    dispatch(session_data, :holdout_complete, %{holdout_id: holdout_id})
  end

  @doc """
  Dispatch an NPC saved event (Soldier rescue missions).
  """
  @spec dispatch_npc_saved(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_npc_saved(session_data, npc_id) do
    dispatch(session_data, :npc_saved, %{npc_id: npc_id})
  end

  @doc """
  Dispatch an escort complete event.
  """
  @spec dispatch_escort_complete(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_escort_complete(session_data, npc_id) do
    dispatch(session_data, :escort_complete, %{npc_id: npc_id})
  end

  @doc """
  Dispatch an object destroyed event.
  """
  @spec dispatch_destroy_object(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_destroy_object(session_data, object_id) do
    dispatch(session_data, :destroy_object, %{object_id: object_id})
  end

  # ============================================================================
  # Explorer-Specific Events
  # ============================================================================

  @doc """
  Dispatch a claim territory event.
  """
  @spec dispatch_claim_territory(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_claim_territory(session_data, territory_id) do
    dispatch(session_data, :claim_territory, %{territory_id: territory_id})
  end

  @doc """
  Dispatch a photograph event.
  """
  @spec dispatch_photograph(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_photograph(session_data, target_id) do
    dispatch(session_data, :photograph, %{target_id: target_id})
  end

  @doc """
  Dispatch a follow trail event.
  """
  @spec dispatch_follow_trail(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_follow_trail(session_data, trail_id) do
    dispatch(session_data, :follow_trail, %{trail_id: trail_id})
  end

  # ============================================================================
  # Scientist-Specific Events
  # ============================================================================

  @doc """
  Dispatch a collect specimen event.
  """
  @spec dispatch_collect_specimen(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_collect_specimen(session_data, specimen_id) do
    dispatch(session_data, :collect_specimen, %{specimen_id: specimen_id})
  end

  @doc """
  Dispatch an analyze event.
  """
  @spec dispatch_analyze(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_analyze(session_data, creature_id) do
    dispatch(session_data, :analyze, %{creature_id: creature_id})
  end

  @doc """
  Dispatch an excavate event (archaeology).
  """
  @spec dispatch_excavate(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_excavate(session_data, site_id) do
    dispatch(session_data, :excavate, %{site_id: site_id})
  end

  @doc """
  Dispatch an observe event (field study).
  """
  @spec dispatch_observe(session_data(), integer()) :: {session_data(), [packet()]}
  def dispatch_observe(session_data, creature_id) do
    dispatch(session_data, :observe, %{creature_id: creature_id})
  end

  # ============================================================================
  # Zone Entry/Exit
  # ============================================================================

  @doc """
  Initialize session data for a zone entry.

  Loads path missions available in the zone for the player's path.
  Should be called when player enters a new zone or logs in.

  ## Parameters

  - `session_data` - Current session data with path info
  - `world_id` - World ID being entered
  - `zone_id` - Zone ID within the world

  ## Required session_data keys

  - `:character_id` - Player's character ID
  - `:path_type` - Player's path (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer)
  - `:faction` - Player's faction (for faction-gated missions)

  ## Example

      # When player enters zone
      {session_data, packets} = EventDispatcher.on_zone_entry(
        state.session_data,
        world_id,
        zone_id
      )
      send_packets(packets, state)
      {:noreply, %{state | session_data: session_data}}
  """
  @spec on_zone_entry(session_data(), integer(), integer()) :: {session_data(), [packet()]}
  def on_zone_entry(session_data, world_id, zone_id) do
    character_id = session_data[:character_id] || 0
    path_type = session_data[:path_type] || 0

    Logger.info(
      "Zone entry: character=#{character_id}, world=#{world_id}, zone=#{zone_id}, path=#{path_name(path_type)}"
    )

    # Store current zone in session
    session_data =
      session_data
      |> Map.put(:current_world_id, world_id)
      |> Map.put(:current_zone_id, zone_id)

    # Initialize path missions for this zone
    {updated_session, path_packets} =
      SessionPathManager.initialize_zone_missions(
        session_data,
        character_id,
        path_type,
        world_id,
        zone_id
      )

    # Also trigger zone entry events for any active quest objectives
    {final_session, quest_packets} =
      dispatch(updated_session, :enter_zone, %{
        world_id: world_id,
        zone_id: zone_id
      })

    {final_session, path_packets ++ quest_packets}
  end

  @doc """
  Clean up session data when leaving a zone.

  Marks zone-specific path missions as abandoned (not completed).
  """
  @spec on_zone_exit(session_data(), integer(), integer()) :: session_data()
  def on_zone_exit(session_data, _world_id, zone_id) do
    # Remove zone-specific missions that weren't completed
    active_missions = session_data[:active_path_missions] || %{}

    # Keep missions that are from other zones or are already completable
    remaining_missions =
      active_missions
      |> Enum.reject(fn {_id, mission} ->
        mission.zone_id == zone_id and mission.state == :active
      end)
      |> Enum.into(%{})

    removed_count = map_size(active_missions) - map_size(remaining_missions)

    if removed_count > 0 do
      Logger.debug("Zone exit: removed #{removed_count} incomplete path missions from zone #{zone_id}")
    end

    Map.put(session_data, :active_path_missions, remaining_missions)
  end

  @doc """
  Initialize session data on login.

  Loads persisted quest and path mission progress into session_data.
  """
  @spec on_login(session_data(), integer()) :: {session_data(), [packet()]}
  def on_login(session_data, character_id) do
    # Load completed path missions from database
    completed_mission_ids =
      case BezgelorDb.Paths.get_completed_missions(character_id) do
        {:ok, ids} -> MapSet.new(ids)
        _ -> MapSet.new()
      end

    session_data =
      session_data
      |> Map.put(:character_id, character_id)
      |> Map.put(:completed_path_mission_ids, completed_mission_ids)
      |> Map.put(:active_path_missions, %{})

    Logger.info("Login: character=#{character_id}, #{MapSet.size(completed_mission_ids)} completed path missions")

    {session_data, []}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp path_name(0), do: "Soldier"
  defp path_name(1), do: "Settler"
  defp path_name(2), do: "Scientist"
  defp path_name(3), do: "Explorer"
  defp path_name(_), do: "Unknown"
end
