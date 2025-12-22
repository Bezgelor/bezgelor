defmodule BezgelorDb.Schema.TelemetryEventTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.TelemetryEvent

  describe "changeset/2" do
    test "valid attributes create valid changeset" do
      attrs = %{
        event_name: "bezgelor.auth.login_complete",
        measurements: %{duration_ms: 150},
        metadata: %{account_id: 1, success: true},
        occurred_at: DateTime.utc_now()
      }

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      assert changeset.valid?
    end

    test "requires event_name" do
      attrs = %{occurred_at: DateTime.utc_now()}
      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_name
    end

    test "requires occurred_at" do
      attrs = %{event_name: "bezgelor.auth.login_complete"}
      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).occurred_at
    end
  end
end
