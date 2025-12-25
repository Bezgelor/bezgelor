defmodule BezgelorWorld.Path.SessionPathManagerTest do
  @moduledoc """
  Tests for SessionPathManager event processing and mission management.
  """
  use ExUnit.Case, async: true

  alias BezgelorWorld.Path.SessionPathManager

  # ============================================================================
  # Mission Type Constants for Testing
  # ============================================================================

  # Soldier mission types
  @type_holdout 0
  @type_assassination 4
  @type_swat 5
  @type_demolition 6
  @type_rescue 7

  # Settler mission types
  @type_infrastructure 19
  # @type_civil_service 21 - unused but kept for reference
  @type_cache 25
  # @type_project 26 - unused but kept for reference
  @type_depot 27

  # Scientist mission types
  @type_scan 2
  @type_datacube 14
  # @type_field_study 20 - unused but kept for reference
  @type_specimen 22
  @type_biology 23
  @type_archaeology 24

  # Explorer mission types
  @type_cartography 3
  @type_surveillance 12
  @type_operations 13
  @type_vista 15
  @type_tracking 16
  @type_scavenger_hunt 17
  @type_stake_claim 18

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  defp build_mission(mission_id, mission_type, object_id, opts \\ []) do
    # Default target is 3 to allow testing progress before auto-completion
    %{
      mission_id: mission_id,
      mission_type: mission_type,
      path_type: Keyword.get(opts, :path_type, 0),
      object_id: object_id,
      location_ids: Keyword.get(opts, :location_ids, []),
      state: Keyword.get(opts, :state, :active),
      progress: Keyword.get(opts, :progress, %{"count" => 0, "target" => 3}),
      dirty: false
    }
  end

  defp session_with_missions(missions) do
    mission_map =
      missions
      |> Enum.map(fn m -> {m.mission_id, m} end)
      |> Enum.into(%{})

    %{
      active_path_missions: mission_map,
      completed_path_mission_ids: MapSet.new()
    }
  end

  # ============================================================================
  # Soldier Mission Tests
  # ============================================================================

  describe "Soldier: Holdout missions (type 0)" do
    test "holdout_wave event increments progress" do
      mission = build_mission(100, @type_holdout, 456)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :holdout_wave, %{holdout_id: 456})

      updated_mission = updated_session[:active_path_missions][100]
      assert updated_mission.progress["count"] == 1
      assert updated_mission.dirty == true
      assert length(packets) >= 1
    end

    test "holdout_complete event with matching holdout_id" do
      mission = build_mission(100, @type_holdout, 789)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :holdout_complete, %{holdout_id: 789})

      updated_mission = updated_session[:active_path_missions][100]
      assert updated_mission.progress["count"] == 1
    end

    test "holdout event with non-matching holdout_id does not increment" do
      mission = build_mission(100, @type_holdout, 456)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :holdout_wave, %{holdout_id: 999})

      updated_mission = updated_session[:active_path_missions][100]
      assert updated_mission.progress["count"] == 0
      assert packets == []
    end
  end

  describe "Soldier: Assassination missions (type 4)" do
    test "kill event increments progress for matching creature_id" do
      mission = build_mission(101, @type_assassination, 12345)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 12345})

      updated_mission = updated_session[:active_path_missions][101]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "kill event does not increment for non-matching creature_id" do
      mission = build_mission(101, @type_assassination, 12345)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 99999})

      updated_mission = updated_session[:active_path_missions][101]
      assert updated_mission.progress["count"] == 0
      assert packets == []
    end
  end

  describe "Soldier: Demolition missions (type 6)" do
    test "destroy_object event increments progress" do
      mission = build_mission(102, @type_demolition, 555)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :destroy_object, %{object_id: 555})

      updated_mission = updated_session[:active_path_missions][102]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end
  end

  describe "Soldier: Rescue missions (type 7)" do
    test "npc_saved event increments progress" do
      mission = build_mission(103, @type_rescue, 777)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :npc_saved, %{npc_id: 777})

      updated_mission = updated_session[:active_path_missions][103]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "escort_complete event increments progress" do
      mission = build_mission(103, @type_rescue, 888)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :escort_complete, %{npc_id: 888})

      updated_mission = updated_session[:active_path_missions][103]
      assert updated_mission.progress["count"] == 1
    end
  end

  # ============================================================================
  # Settler Mission Tests
  # ============================================================================

  describe "Settler: Infrastructure missions (type 19)" do
    test "build event increments progress" do
      mission = build_mission(200, @type_infrastructure, 1001, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :build, %{structure_id: 1001})

      updated_mission = updated_session[:active_path_missions][200]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "repair event increments progress" do
      mission = build_mission(200, @type_infrastructure, 1002, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :repair, %{structure_id: 1002})

      updated_mission = updated_session[:active_path_missions][200]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Settler: Cache missions (type 25)" do
    test "loot event with cache_id increments progress" do
      mission = build_mission(201, @type_cache, 2001, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :loot, %{cache_id: 2001})

      updated_mission = updated_session[:active_path_missions][201]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "discover event with cache_id increments progress" do
      mission = build_mission(201, @type_cache, 2002, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :discover, %{cache_id: 2002})

      updated_mission = updated_session[:active_path_missions][201]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Settler: Depot missions (type 27)" do
    test "depot_placed event increments progress" do
      mission = build_mission(202, @type_depot, 50, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :depot_placed, %{depot_type: 50})

      updated_mission = updated_session[:active_path_missions][202]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "depot_placed with object_id 0 matches any depot_type" do
      mission = build_mission(202, @type_depot, 0, path_type: 1)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :depot_placed, %{depot_type: 99})

      updated_mission = updated_session[:active_path_missions][202]
      assert updated_mission.progress["count"] == 1
    end
  end

  # ============================================================================
  # Scientist Mission Tests
  # ============================================================================

  describe "Scientist: Scan missions (type 2)" do
    test "scan event increments progress for matching target_id" do
      mission = build_mission(300, @type_scan, 3001, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :scan, %{target_id: 3001})

      updated_mission = updated_session[:active_path_missions][300]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "scan event with object_id 0 matches any target" do
      mission = build_mission(300, @type_scan, 0, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :scan, %{target_id: 99999})

      updated_mission = updated_session[:active_path_missions][300]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Scientist: Datacube missions (type 14)" do
    test "datacube event increments progress" do
      mission = build_mission(301, @type_datacube, 4001, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :datacube, %{datacube_id: 4001})

      updated_mission = updated_session[:active_path_missions][301]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end
  end

  describe "Scientist: Specimen missions (type 22)" do
    test "collect_specimen event increments progress" do
      mission = build_mission(302, @type_specimen, 5001, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :collect_specimen, %{specimen_id: 5001})

      updated_mission = updated_session[:active_path_missions][302]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "loot event with item_id increments progress" do
      mission = build_mission(302, @type_specimen, 5002, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :loot, %{item_id: 5002})

      updated_mission = updated_session[:active_path_missions][302]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Scientist: Biology missions (type 23)" do
    test "analyze event increments progress" do
      mission = build_mission(303, @type_biology, 6001, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :analyze, %{creature_id: 6001})

      updated_mission = updated_session[:active_path_missions][303]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end
  end

  describe "Scientist: Archaeology missions (type 24)" do
    test "excavate event increments progress" do
      mission = build_mission(304, @type_archaeology, 7001, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :excavate, %{site_id: 7001})

      updated_mission = updated_session[:active_path_missions][304]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "discover event with artifact_id increments progress" do
      mission = build_mission(304, @type_archaeology, 7002, path_type: 2)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :discover, %{artifact_id: 7002})

      updated_mission = updated_session[:active_path_missions][304]
      assert updated_mission.progress["count"] == 1
    end
  end

  # ============================================================================
  # Explorer Mission Tests
  # ============================================================================

  describe "Explorer: Vista missions (type 15)" do
    test "reach_location event increments progress when location in list" do
      mission = build_mission(400, @type_vista, 0, path_type: 3, location_ids: [8001, 8002, 8003])
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :reach_location, %{location_id: 8001})

      updated_mission = updated_session[:active_path_missions][400]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "reach_location does not increment when location not in list" do
      mission = build_mission(400, @type_vista, 0, path_type: 3, location_ids: [8001, 8002])
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :reach_location, %{location_id: 99999})

      updated_mission = updated_session[:active_path_missions][400]
      assert updated_mission.progress["count"] == 0
      assert packets == []
    end

    test "enter_area event increments progress" do
      mission = build_mission(400, @type_vista, 0, path_type: 3, location_ids: [8001])
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :enter_area, %{area_id: 8001})

      updated_mission = updated_session[:active_path_missions][400]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Explorer: Cartography missions (type 3)" do
    test "discover_area event increments progress" do
      mission = build_mission(401, @type_cartography, 9001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :discover_area, %{area_id: 9001})

      updated_mission = updated_session[:active_path_missions][401]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end
  end

  describe "Explorer: Surveillance missions (type 12)" do
    test "observe event increments progress" do
      mission = build_mission(402, @type_surveillance, 10001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :observe, %{target_id: 10001})

      updated_mission = updated_session[:active_path_missions][402]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "photograph event increments progress" do
      mission = build_mission(402, @type_surveillance, 10002, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :photograph, %{target_id: 10002})

      updated_mission = updated_session[:active_path_missions][402]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Explorer: Scavenger Hunt missions (type 17)" do
    test "loot event increments progress" do
      mission = build_mission(403, @type_scavenger_hunt, 11001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :loot, %{item_id: 11001})

      updated_mission = updated_session[:active_path_missions][403]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "discover event with object_id increments progress" do
      mission = build_mission(403, @type_scavenger_hunt, 11002, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :discover, %{object_id: 11002})

      updated_mission = updated_session[:active_path_missions][403]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Explorer: Stake Claim missions (type 18)" do
    test "claim_territory event increments progress" do
      mission = build_mission(404, @type_stake_claim, 12001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :claim_territory, %{territory_id: 12001})

      updated_mission = updated_session[:active_path_missions][404]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end
  end

  describe "Explorer: Tracking missions (type 16)" do
    test "follow_trail event increments progress" do
      mission = build_mission(405, @type_tracking, 13001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :follow_trail, %{trail_id: 13001})

      updated_mission = updated_session[:active_path_missions][405]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "reach_location event increments progress for tracking" do
      mission = build_mission(405, @type_tracking, 0, path_type: 3, location_ids: [13002])
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :reach_location, %{location_id: 13002})

      updated_mission = updated_session[:active_path_missions][405]
      assert updated_mission.progress["count"] == 1
    end
  end

  describe "Explorer: Operations missions (type 13)" do
    test "interact event increments progress" do
      mission = build_mission(406, @type_operations, 14001, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :interact, %{object_id: 14001})

      updated_mission = updated_session[:active_path_missions][406]
      assert updated_mission.progress["count"] == 1
      assert length(packets) >= 1
    end

    test "complete_objective event increments progress" do
      mission = build_mission(406, @type_operations, 14002, path_type: 3)
      session = session_with_missions([mission])

      {updated_session, _packets} =
        SessionPathManager.process_game_event(session, :complete_objective, %{objective_id: 14002})

      updated_mission = updated_session[:active_path_missions][406]
      assert updated_mission.progress["count"] == 1
    end
  end

  # ============================================================================
  # General Mission Management Tests
  # ============================================================================

  describe "Mission state management" do
    test "inactive missions are not processed" do
      mission = build_mission(500, @type_assassination, 999, state: :completable)
      session = session_with_missions([mission])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 999})

      # Mission should not be updated since it's not active
      updated_mission = updated_session[:active_path_missions][500]
      assert updated_mission.progress["count"] == 0
      assert packets == []
    end

    test "mission auto-completes when target reached" do
      mission =
        build_mission(501, @type_assassination, 123, progress: %{"count" => 0, "target" => 2})

      session = session_with_missions([mission])

      # Kill once - not yet complete
      {session, _} = SessionPathManager.process_game_event(session, :kill, %{creature_id: 123})
      assert session[:active_path_missions][501] != nil
      assert session[:active_path_missions][501].progress["count"] == 1

      # Kill again - reaches target, auto-completes
      {session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 123})

      # Mission is removed from active (completed)
      assert session[:active_path_missions][501] == nil

      # Completion packet was sent
      assert Enum.any?(packets, fn {type, _} -> type == :server_path_mission_complete end)

      # Additional kills have no effect
      {_session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 123})

      assert packets == []
    end

    test "multiple missions can receive the same event" do
      mission1 = build_mission(600, @type_assassination, 5000)
      # SWAT also triggers on kill
      mission2 = build_mission(601, @type_swat, 5000)
      session = session_with_missions([mission1, mission2])

      {updated_session, packets} =
        SessionPathManager.process_game_event(session, :kill, %{creature_id: 5000, zone_id: 1})

      updated_mission1 = updated_session[:active_path_missions][600]
      updated_mission2 = updated_session[:active_path_missions][601]

      assert updated_mission1.progress["count"] == 1
      assert updated_mission2.progress["count"] == 1
      assert length(packets) >= 2
    end
  end

  describe "abandon_mission/2" do
    test "removes mission from active_path_missions" do
      mission = build_mission(700, @type_scan, 1000, path_type: 2)
      session = session_with_missions([mission])

      updated_session = SessionPathManager.abandon_mission(session, 700)

      assert updated_session[:active_path_missions] == %{}
    end

    test "handles abandoning non-existent mission gracefully" do
      session = %{active_path_missions: %{}}
      updated_session = SessionPathManager.abandon_mission(session, 99999)
      assert updated_session[:active_path_missions] == %{}
    end
  end

  describe "get_active_by_path/2" do
    test "filters missions by path type" do
      soldier_mission = build_mission(800, @type_holdout, 100, path_type: 0)
      scientist_mission = build_mission(801, @type_scan, 200, path_type: 2)
      explorer_mission = build_mission(802, @type_vista, 0, path_type: 3, location_ids: [300])
      session = session_with_missions([soldier_mission, scientist_mission, explorer_mission])

      scientist_missions = SessionPathManager.get_active_by_path(session, 2)

      assert length(scientist_missions) == 1
      assert hd(scientist_missions).mission_id == 801
    end

    test "returns empty list for path with no missions" do
      mission = build_mission(800, @type_holdout, 100, path_type: 0)
      session = session_with_missions([mission])

      settler_missions = SessionPathManager.get_active_by_path(session, 1)
      assert settler_missions == []
    end
  end
end
