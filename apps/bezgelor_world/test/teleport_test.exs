defmodule BezgelorWorld.TeleportTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Teleport
  alias BezgelorWorld.Zone.InstanceSupervisor
  alias BezgelorCore.Entity

  describe "to_world_location/2" do
    test "returns error for non-existent world location" do
      # World location ID that doesn't exist
      fake_session = %{
        session_data: %{
          player_guid: 1,
          zone_id: 1,
          instance_id: 1
        }
      }

      assert {:error, :invalid_location} = Teleport.to_world_location(fake_session, 999_999_999)
    end
  end

  describe "to_position/4" do
    setup do
      # Create a test zone instance
      zone_id = System.unique_integer([:positive])
      instance_id = 1
      world_id = 426

      zone_data = %{id: zone_id, name: "Test Zone"}
      {:ok, _pid} = InstanceSupervisor.start_instance(zone_id, instance_id, zone_data)

      on_exit(fn ->
        InstanceSupervisor.stop_instance(zone_id, instance_id)
      end)

      %{zone_id: zone_id, instance_id: instance_id, world_id: world_id}
    end

    test "returns error for invalid world_id" do
      fake_session = %{
        session_data: %{
          player_guid: 1,
          zone_id: 1,
          instance_id: 1
        }
      }

      assert {:error, :invalid_world} = Teleport.to_position(fake_session, 0, {0.0, 0.0, 0.0})
    end

    test "teleports player to new position in same zone", %{zone_id: zone_id, instance_id: instance_id, world_id: world_id} do
      player_guid = System.unique_integer([:positive])

      # Add player entity to zone
      player = %Entity{
        guid: player_guid,
        type: :player,
        name: "TestPlayer",
        position: {0.0, 0.0, 0.0}
      }

      BezgelorWorld.Zone.Instance.add_entity({zone_id, instance_id}, player)
      Process.sleep(10)

      session = %{
        session_data: %{
          player_guid: player_guid,
          zone_id: zone_id,
          instance_id: instance_id,
          world_id: world_id,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      new_position = {100.0, 50.0, 200.0}
      new_rotation = {0.0, 0.0, 1.57}

      assert {:ok, updated_session} = Teleport.to_position(session, world_id, new_position, new_rotation)

      # Verify session was updated
      assert updated_session.session_data.spawn_location.position == new_position
    end

    test "teleports player to different zone", %{zone_id: zone_id, instance_id: instance_id} do
      player_guid = System.unique_integer([:positive])

      session = %{
        session_data: %{
          player_guid: player_guid,
          zone_id: zone_id,
          instance_id: instance_id,
          world_id: 426,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      # Teleport to different world
      new_world_id = 1387
      new_position = {-3835.0, -980.0, -6050.0}

      assert {:ok, updated_session} = Teleport.to_position(session, new_world_id, new_position)

      # Verify session was updated with new world
      assert updated_session.session_data.world_id == new_world_id
      assert updated_session.session_data.spawn_location.world_id == new_world_id
    end
  end

  describe "build_spawn_from_world_location/1" do
    test "converts world location data to spawn format" do
      world_location = %{
        "ID" => 100,
        "worldId" => 426,
        "worldZoneId" => 1,
        "position0" => 100.0,
        "position1" => 50.0,
        "position2" => 200.0,
        "facing0" => 0.0,
        "facing1" => 0.0,
        "facing2" => 0.0,
        "facing3" => 1.0
      }

      spawn = Teleport.build_spawn_from_world_location(world_location)

      assert spawn.world_id == 426
      assert spawn.zone_id == 1
      assert spawn.position == {100.0, 50.0, 200.0}
      # Quaternion to euler: facing3=1.0 with others 0 => yaw=0
      assert spawn.rotation == {0.0, 0.0, 0.0}
    end
  end
end
