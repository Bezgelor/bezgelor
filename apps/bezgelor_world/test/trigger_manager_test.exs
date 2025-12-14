defmodule BezgelorWorld.TriggerManagerTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.TriggerManager

  describe "build_trigger/1" do
    test "builds trigger from world location data" do
      world_location = %{
        "ID" => 50231,
        "worldId" => 1634,
        "worldZoneId" => 4844,
        "position0" => 4088.0,
        "position1" => -7.5,
        "position2" => -3.6,
        "radius" => 5.0
      }

      trigger = TriggerManager.build_trigger(world_location)

      assert trigger.id == 50231
      assert trigger.world_id == 1634
      assert trigger.zone_id == 4844
      assert trigger.position == {4088.0, -7.5, -3.6}
      assert trigger.radius == 5.0
    end

    test "uses default radius of 3.0 when radius is 0 or 1" do
      world_location = %{
        "ID" => 100,
        "worldId" => 426,
        "worldZoneId" => 1,
        "position0" => 0.0,
        "position1" => 0.0,
        "position2" => 0.0,
        "radius" => 1.0
      }

      trigger = TriggerManager.build_trigger(world_location)
      assert trigger.radius == 3.0
    end
  end

  describe "in_trigger?/2" do
    test "returns true when position is within trigger radius" do
      trigger = %{
        id: 1,
        position: {100.0, 50.0, 200.0},
        radius: 10.0
      }

      assert TriggerManager.in_trigger?({100.0, 50.0, 200.0}, trigger) == true
      assert TriggerManager.in_trigger?({105.0, 50.0, 200.0}, trigger) == true
      assert TriggerManager.in_trigger?({100.0, 55.0, 205.0}, trigger) == true
    end

    test "returns false when position is outside trigger radius" do
      trigger = %{
        id: 1,
        position: {100.0, 50.0, 200.0},
        radius: 10.0
      }

      assert TriggerManager.in_trigger?({200.0, 50.0, 200.0}, trigger) == false
      assert TriggerManager.in_trigger?({100.0, 100.0, 200.0}, trigger) == false
    end
  end

  describe "check_triggers/4" do
    test "returns list of newly entered trigger IDs" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0},
        %{id: 2, position: {100.0, 0.0, 0.0}, radius: 10.0},
        %{id: 3, position: {200.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move from outside to inside trigger 1
      old_position = {-50.0, 0.0, 0.0}
      new_position = {0.0, 0.0, 0.0}
      active_triggers = MapSet.new()

      {entered, _exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert entered == [1]
    end

    test "tracks trigger exit" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move from inside to outside trigger 1
      old_position = {0.0, 0.0, 0.0}
      new_position = {50.0, 0.0, 0.0}
      active_triggers = MapSet.new([1])

      {_entered, exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert exited == [1]
    end

    test "does not re-fire for triggers player is already in" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move within trigger 1
      old_position = {0.0, 0.0, 0.0}
      new_position = {5.0, 0.0, 0.0}
      active_triggers = MapSet.new([1])

      {entered, exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert entered == []
      assert exited == []
    end
  end
end
