defmodule BezgelorCore.TelemetryEventTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.TelemetryEvent

  describe "validate/1" do
    test "validates a correct event definition" do
      event = %{
        event: [:bezgelor, :auth, :login],
        measurements: [:duration_ms, :success],
        tags: [:account_id],
        description: "User login attempt",
        domain: :auth
      }

      assert :ok = TelemetryEvent.validate(event)
    end

    test "returns error for missing event key" do
      event = %{measurements: [:count], tags: [], description: "test", domain: :test}
      assert {:error, "missing required key: event"} = TelemetryEvent.validate(event)
    end

    test "returns error for non-list event" do
      event = %{event: "bad", measurements: [], tags: [], description: "test", domain: :test}
      assert {:error, "event must be a list of atoms"} = TelemetryEvent.validate(event)
    end
  end

  describe "to_metric_def/1" do
    test "converts event to telemetry_metrics summary definition" do
      event = %{
        event: [:bezgelor, :auth, :login],
        measurements: [:duration_ms],
        tags: [:account_id],
        description: "Login duration",
        domain: :auth
      }

      result = TelemetryEvent.to_metric_def(event, :summary)

      assert is_list(result)
      assert length(result) == 1
      [metric] = result
      assert metric.name == "bezgelor.auth.login.duration_ms"
      assert metric.measurement == :duration_ms
      assert metric.tags == [:account_id]
      assert metric.description == "Login duration"
    end

    test "generates multiple metrics for multiple measurements" do
      event = %{
        event: [:bezgelor, :combat, :spell],
        measurements: [:count, :damage],
        tags: [:spell_id],
        description: "Spell cast",
        domain: :combat
      }

      result = TelemetryEvent.to_metric_def(event, :counter)

      assert length(result) == 2
      names = Enum.map(result, & &1.name)
      assert "bezgelor.combat.spell.count" in names
      assert "bezgelor.combat.spell.damage" in names
    end
  end

  describe "event_name/1" do
    test "returns dot-separated event name" do
      event = %{
        event: [:bezgelor, :server, :player_connected],
        measurements: [:count],
        tags: [],
        description: "Player connected",
        domain: :server
      }

      assert TelemetryEvent.event_name(event) == "bezgelor.server.player_connected"
    end
  end
end
