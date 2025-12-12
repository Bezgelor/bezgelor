defmodule BezgelorDb.Schema.EventScheduleTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.EventSchedule

  @valid_attrs %{
    event_id: 1001,
    zone_id: 100,
    enabled: true,
    trigger_type: :timer,
    trigger_config: %{"interval_hours" => 2, "offset_minutes" => 30}
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = EventSchedule.changeset(%EventSchedule{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with minimal required fields" do
      attrs = %{event_id: 1001, zone_id: 100, trigger_type: :timer}
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end

    test "invalid without event_id" do
      attrs = Map.delete(@valid_attrs, :event_id)
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_id
    end

    test "invalid without zone_id" do
      attrs = Map.delete(@valid_attrs, :zone_id)
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).zone_id
    end

    test "invalid without trigger_type" do
      attrs = Map.delete(@valid_attrs, :trigger_type)
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).trigger_type
    end

    test "accepts all valid trigger types" do
      for trigger <- EventSchedule.valid_trigger_types() do
        attrs = Map.put(@valid_attrs, :trigger_type, trigger)
        changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
        assert changeset.valid?, "Expected trigger_type #{trigger} to be valid"
      end
    end

    test "defaults enabled to true" do
      changeset = EventSchedule.changeset(%EventSchedule{}, %{event_id: 1, zone_id: 1, trigger_type: :timer})
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
    end

    test "defaults trigger_config to empty map" do
      changeset = EventSchedule.changeset(%EventSchedule{}, %{event_id: 1, zone_id: 1, trigger_type: :timer})
      assert Ecto.Changeset.get_field(changeset, :trigger_config) == %{}
    end

    test "accepts timer trigger config" do
      attrs = Map.put(@valid_attrs, :trigger_config, %{"interval_hours" => 4, "offset_minutes" => 15})
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end

    test "accepts random_window trigger config" do
      attrs = %{
        event_id: 1001,
        zone_id: 100,
        trigger_type: :random_window,
        trigger_config: %{"start_hour" => 18, "end_hour" => 22, "min_gap_hours" => 4}
      }
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end

    test "accepts player_count trigger config" do
      attrs = %{
        event_id: 1001,
        zone_id: 100,
        trigger_type: :player_count,
        trigger_config: %{"min_players" => 10, "check_interval_ms" => 60000}
      }
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end

    test "accepts chain trigger config" do
      attrs = %{
        event_id: 1001,
        zone_id: 100,
        trigger_type: :chain,
        trigger_config: %{"after_event_id" => 1002, "delay_ms" => 30000}
      }
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end

    test "accepts manual trigger type" do
      attrs = %{event_id: 1001, zone_id: 100, trigger_type: :manual}
      changeset = EventSchedule.changeset(%EventSchedule{}, attrs)
      assert changeset.valid?
    end
  end

  describe "enable_changeset/1" do
    test "sets enabled to true" do
      schedule = %EventSchedule{enabled: false}

      changeset = EventSchedule.enable_changeset(schedule)

      assert Ecto.Changeset.get_change(changeset, :enabled) == true
    end
  end

  describe "disable_changeset/1" do
    test "sets enabled to false" do
      schedule = %EventSchedule{enabled: true}

      changeset = EventSchedule.disable_changeset(schedule)

      assert Ecto.Changeset.get_change(changeset, :enabled) == false
    end
  end

  describe "trigger_changeset/3" do
    test "updates last_triggered_at and next_trigger_at" do
      schedule = %EventSchedule{last_triggered_at: nil, next_trigger_at: nil}
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      next = DateTime.add(now, 7200, :second)

      changeset = EventSchedule.trigger_changeset(schedule, now, next)

      assert Ecto.Changeset.get_change(changeset, :last_triggered_at) == now
      assert Ecto.Changeset.get_change(changeset, :next_trigger_at) == next
    end
  end

  describe "update_next_trigger_changeset/2" do
    test "updates next_trigger_at" do
      schedule = %EventSchedule{next_trigger_at: nil}
      next = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

      changeset = EventSchedule.update_next_trigger_changeset(schedule, next)

      assert Ecto.Changeset.get_change(changeset, :next_trigger_at) == next
    end
  end

  describe "valid_trigger_types/0" do
    test "returns list of valid trigger types" do
      types = EventSchedule.valid_trigger_types()
      assert :timer in types
      assert :random_window in types
      assert :player_count in types
      assert :chain in types
      assert :manual in types
    end
  end
end
