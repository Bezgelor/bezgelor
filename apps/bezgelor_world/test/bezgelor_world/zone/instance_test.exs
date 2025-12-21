defmodule BezgelorWorld.World.InstanceTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  setup do
    # InstanceSupervisor is already started by the application
    # Generate unique world/instance IDs for each test
    # World.Instance is keyed by world_id
    world_id = System.unique_integer([:positive])
    instance_id = 1

    world_data = %{
      id: world_id,
      name: "Test World",
      min_level: 1,
      max_level: 10
    }

    {:ok, pid} = InstanceSupervisor.start_instance(world_id, instance_id, world_data)

    on_exit(fn ->
      InstanceSupervisor.stop_instance(world_id, instance_id)
    end)

    %{world_id: world_id, instance_id: instance_id, pid: pid}
  end

  describe "add_entity/2" do
    test "adds player entity to world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{
        guid: 12345,
        type: :player,
        name: "TestPlayer",
        position: {100.0, 50.0, 200.0}
      }

      :ok = Instance.add_entity({world_id, instance_id}, entity)

      {:ok, retrieved} = Instance.get_entity({world_id, instance_id}, 12345)
      assert retrieved.name == "TestPlayer"
    end

    test "adds creature entity to world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{
        guid: 99999,
        type: :creature,
        name: "TestCreature",
        position: {0.0, 0.0, 0.0}
      }

      :ok = Instance.add_entity({world_id, instance_id}, entity)

      {:ok, retrieved} = Instance.get_entity({world_id, instance_id}, 99999)
      assert retrieved.name == "TestCreature"
    end
  end

  describe "remove_entity/2" do
    test "removes entity from world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{guid: 12345, type: :player, name: "Test"}

      Instance.add_entity({world_id, instance_id}, entity)
      Instance.remove_entity({world_id, instance_id}, 12345)

      assert :error = Instance.get_entity({world_id, instance_id}, 12345)
    end
  end

  describe "get_entity/2" do
    test "returns :error for nonexistent entity", %{world_id: world_id, instance_id: instance_id} do
      assert :error = Instance.get_entity({world_id, instance_id}, 99999)
    end
  end

  describe "update_entity/3" do
    test "updates entity state", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{guid: 12345, type: :player, name: "Test", health: 100}

      Instance.add_entity({world_id, instance_id}, entity)

      :ok =
        Instance.update_entity({world_id, instance_id}, 12345, fn e ->
          %{e | health: 50}
        end)

      {:ok, updated} = Instance.get_entity({world_id, instance_id}, 12345)
      assert updated.health == 50
    end

    test "returns :error for nonexistent entity", %{world_id: world_id, instance_id: instance_id} do
      assert :error = Instance.update_entity({world_id, instance_id}, 99999, fn e -> e end)
    end
  end

  describe "entities_in_range/3" do
    test "finds entities within range", %{world_id: world_id, instance_id: instance_id} do
      # Add entities at various positions
      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 1,
        type: :player,
        position: {0.0, 0.0, 0.0}
      })

      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 2,
        type: :player,
        position: {50.0, 0.0, 0.0}
      })

      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 3,
        type: :player,
        position: {200.0, 0.0, 0.0}
      })

      # Find entities within 100 units of origin
      entities = Instance.entities_in_range({world_id, instance_id}, {0.0, 0.0, 0.0}, 100.0)

      guids = Enum.map(entities, & &1.guid) |> Enum.sort()
      assert guids == [1, 2]
    end

    test "returns empty list when no entities in range", %{
      world_id: world_id,
      instance_id: instance_id
    } do
      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 1,
        type: :player,
        position: {1000.0, 1000.0, 1000.0}
      })

      entities = Instance.entities_in_range({world_id, instance_id}, {0.0, 0.0, 0.0}, 10.0)
      assert entities == []
    end
  end

  describe "list_players/1" do
    test "returns only player entities", %{world_id: world_id, instance_id: instance_id} do
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 1, type: :player, name: "Player1"})

      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature, name: "Mob"})

      Instance.add_entity({world_id, instance_id}, %Entity{guid: 3, type: :player, name: "Player2"})

      players = Instance.list_players({world_id, instance_id})

      assert length(players) == 2
      assert Enum.all?(players, fn p -> p.type == :player end)
    end
  end

  describe "player_count/1" do
    test "returns count of players", %{world_id: world_id, instance_id: instance_id} do
      assert Instance.player_count({world_id, instance_id}) == 0

      Instance.add_entity({world_id, instance_id}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 3, type: :player})

      # Give time for casts to process
      Process.sleep(10)

      assert Instance.player_count({world_id, instance_id}) == 2
    end
  end

  describe "info/1" do
    test "returns world instance information", %{world_id: world_id, instance_id: instance_id} do
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature})

      # Give time for casts to process
      Process.sleep(10)

      info = Instance.info({world_id, instance_id})

      assert info.world_id == world_id
      assert info.instance_id == instance_id
      assert info.world_name == "Test World"
      assert info.player_count == 1
      assert info.creature_count == 1
      assert info.total_entities == 2
    end
  end
end
