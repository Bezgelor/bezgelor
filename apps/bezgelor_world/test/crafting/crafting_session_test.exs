defmodule BezgelorWorld.Crafting.CraftingSessionTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.Crafting.CraftingSession

  describe "new/1" do
    test "creates session with initial cursor at origin" do
      session = CraftingSession.new(1234)
      assert session.schematic_id == 1234
      assert session.cursor_x == 0.0
      assert session.cursor_y == 0.0
      assert session.additives_used == []
      assert session.overcharge_level == 0
    end
  end

  describe "add_additive/2" do
    test "updates cursor position and records additive" do
      session = CraftingSession.new(1234)
      additive = %{item_id: 100, quantity: 1, vector_x: 10.0, vector_y: 5.0}

      updated = CraftingSession.add_additive(session, additive)

      assert updated.cursor_x == 10.0
      assert updated.cursor_y == 5.0
      assert length(updated.additives_used) == 1
    end

    test "accumulates multiple additives" do
      session = CraftingSession.new(1234)
      additive1 = %{item_id: 100, quantity: 1, vector_x: 10.0, vector_y: 5.0}
      additive2 = %{item_id: 101, quantity: 1, vector_x: -3.0, vector_y: 8.0}

      updated =
        session
        |> CraftingSession.add_additive(additive1)
        |> CraftingSession.add_additive(additive2)

      assert updated.cursor_x == 7.0
      assert updated.cursor_y == 13.0
      assert length(updated.additives_used) == 2
    end
  end

  describe "set_overcharge/2" do
    test "sets overcharge level" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, 2)
      assert updated.overcharge_level == 2
    end

    test "clamps to max level 3" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, 5)
      assert updated.overcharge_level == 3
    end

    test "clamps to min level 0" do
      session = CraftingSession.new(1234)
      updated = CraftingSession.set_overcharge(session, -1)
      assert updated.overcharge_level == 0
    end
  end

  describe "get_cursor/1" do
    test "returns cursor as tuple" do
      session = %CraftingSession{cursor_x: 25.5, cursor_y: 30.0, schematic_id: 1}
      assert CraftingSession.get_cursor(session) == {25.5, 30.0}
    end
  end
end
