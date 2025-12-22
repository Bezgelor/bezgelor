defmodule BezgelorDb.Schema.TelemetryBucketTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.TelemetryBucket

  describe "changeset/2" do
    test "valid minute bucket" do
      attrs = %{
        event_name: "bezgelor.auth.login_complete",
        bucket_type: :minute,
        bucket_start: ~U[2025-12-21 14:32:00Z],
        count: 23,
        sum_values: %{duration_ms: 3450},
        min_values: %{duration_ms: 50},
        max_values: %{duration_ms: 500},
        metadata_counts: %{"success:true" => 20, "success:false" => 3}
      }

      changeset = TelemetryBucket.changeset(%TelemetryBucket{}, attrs)
      assert changeset.valid?
    end

    test "requires bucket_type" do
      attrs = %{event_name: "test", bucket_start: DateTime.utc_now(), count: 1}
      changeset = TelemetryBucket.changeset(%TelemetryBucket{}, attrs)
      refute changeset.valid?
    end
  end
end
