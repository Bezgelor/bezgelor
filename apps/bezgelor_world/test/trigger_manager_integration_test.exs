defmodule BezgelorWorld.TriggerManagerIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.TriggerManager

  describe "load_zone_triggers/1" do
    test "loads triggers for tutorial zone" do
      # Zone 4844 is the Exile tutorial zone
      triggers = TriggerManager.load_zone_triggers(4844)

      # Should have some triggers (world locations)
      assert is_list(triggers)
      # Triggers should have required fields
      for trigger <- triggers do
        assert Map.has_key?(trigger, :id)
        assert Map.has_key?(trigger, :position)
        assert Map.has_key?(trigger, :radius)
      end
    end

    test "loads triggers for a world" do
      # World 1634 is the Exile tutorial ship
      triggers = TriggerManager.load_world_triggers(1634)

      assert is_list(triggers)
    end
  end

  describe "full trigger flow" do
    test "detects trigger entry and exit" do
      # Create a test trigger
      triggers = [
        %{id: 1, position: {100.0, 0.0, 100.0}, radius: 10.0}
      ]

      # Player starts outside
      active = MapSet.new()

      {entered, exited, active} =
        TriggerManager.check_triggers(
          triggers,
          {0.0, 0.0, 0.0},
          {0.0, 0.0, 0.0},
          active
        )

      assert entered == []
      assert exited == []

      # Player moves into trigger
      {entered, exited, active} =
        TriggerManager.check_triggers(
          triggers,
          {0.0, 0.0, 0.0},
          {100.0, 0.0, 100.0},
          active
        )

      assert entered == [1]
      assert exited == []
      assert MapSet.member?(active, 1)

      # Player moves within trigger (no re-fire)
      {entered, exited, active} =
        TriggerManager.check_triggers(
          triggers,
          {100.0, 0.0, 100.0},
          {105.0, 0.0, 100.0},
          active
        )

      assert entered == []
      assert exited == []

      # Player exits trigger
      {entered, exited, _active} =
        TriggerManager.check_triggers(
          triggers,
          {105.0, 0.0, 100.0},
          {200.0, 0.0, 200.0},
          active
        )

      assert entered == []
      assert exited == [1]
    end

    test "handles multiple triggers" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0},
        %{id: 2, position: {5.0, 0.0, 0.0}, radius: 10.0},
        %{id: 3, position: {100.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Player enters overlapping triggers 1 and 2
      {entered, _exited, active} =
        TriggerManager.check_triggers(
          triggers,
          {-50.0, 0.0, 0.0},
          {0.0, 0.0, 0.0},
          MapSet.new()
        )

      # Should enter both overlapping triggers
      assert 1 in entered
      assert 2 in entered
      assert MapSet.member?(active, 1)
      assert MapSet.member?(active, 2)
    end
  end
end
