defmodule BezgelorWorld.Gathering.GatheringNodeTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Gathering.GatheringNode

  describe "new/3" do
    test "creates node at position" do
      position = {100.0, 50.0, 200.0}
      node = GatheringNode.new(1, 100, position)

      assert node.node_id == 1
      assert node.node_type_id == 100
      assert node.position == position
      assert node.respawn_at == nil
      assert node.tapped_by == nil
    end
  end

  describe "available?/1" do
    test "returns true when not respawning and not tapped" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      assert GatheringNode.available?(node)
    end

    test "returns false when respawning" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        respawn_at: future
      }

      refute GatheringNode.available?(node)
    end

    test "returns true when respawn time has passed" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)

      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        respawn_at: past
      }

      assert GatheringNode.available?(node)
    end

    test "returns false when tapped by another player" do
      future = DateTime.add(DateTime.utc_now(), 5, :second)

      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: future
      }

      refute GatheringNode.available?(node)
    end
  end

  describe "tap/2" do
    test "sets tapped_by and expiry" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      tapped = GatheringNode.tap(node, 456)

      assert tapped.tapped_by == 456
      assert tapped.tap_expires_at != nil
    end
  end

  describe "harvest/2" do
    test "sets respawn time" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      harvested = GatheringNode.harvest(node, 30)

      assert harvested.respawn_at != nil
      assert harvested.tapped_by == nil
    end
  end

  describe "can_harvest?/2" do
    test "returns true for tapper" do
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: DateTime.add(DateTime.utc_now(), 5, :second)
      }

      assert GatheringNode.can_harvest?(node, 123)
    end

    test "returns false for non-tapper when tapped" do
      node = %GatheringNode{
        node_id: 1,
        node_type_id: 100,
        position: {0, 0, 0},
        tapped_by: 123,
        tap_expires_at: DateTime.add(DateTime.utc_now(), 5, :second)
      }

      refute GatheringNode.can_harvest?(node, 456)
    end

    test "returns true for anyone when not tapped" do
      node = GatheringNode.new(1, 100, {0, 0, 0})
      assert GatheringNode.can_harvest?(node, 456)
    end
  end
end
