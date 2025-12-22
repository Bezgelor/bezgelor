defmodule BezgelorDb.MetricsTest do
  use ExUnit.Case

  alias BezgelorDb.{Metrics, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "insert_events/1" do
    test "batch inserts multiple events" do
      events = [
        %{
          event_name: "bezgelor.auth.login_complete",
          measurements: %{duration_ms: 100},
          metadata: %{success: true},
          occurred_at: DateTime.utc_now()
        },
        %{
          event_name: "bezgelor.auth.login_complete",
          measurements: %{duration_ms: 200},
          metadata: %{success: false},
          occurred_at: DateTime.utc_now()
        }
      ]

      assert {:ok, 2} = Metrics.insert_events(events)
    end

    test "returns {:ok, 0} for empty list" do
      assert {:ok, 0} = Metrics.insert_events([])
    end
  end

  describe "query_events/3" do
    test "queries events by name and time range" do
      now = DateTime.utc_now()

      Metrics.insert_events([
        %{
          event_name: "test.event",
          measurements: %{value: 1},
          metadata: %{},
          occurred_at: now
        }
      ])

      from = DateTime.add(now, -60, :second)
      to = DateTime.add(now, 60, :second)

      events = Metrics.query_events("test.event", from, to)
      assert length(events) == 1
    end

    test "respects time range boundaries" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -3600, :second)

      Metrics.insert_events([
        %{event_name: "test.event", measurements: %{}, metadata: %{}, occurred_at: old}
      ])

      # Query for last 30 minutes only
      from = DateTime.add(now, -1800, :second)
      to = now

      events = Metrics.query_events("test.event", from, to)
      assert length(events) == 0
    end
  end

  describe "upsert_bucket/1" do
    test "inserts new bucket" do
      bucket_start = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        event_name: "test.event",
        bucket_type: :minute,
        bucket_start: bucket_start,
        count: 5,
        sum_values: %{"duration_ms" => 500},
        min_values: %{"duration_ms" => 50},
        max_values: %{"duration_ms" => 150},
        metadata_counts: %{"success:true" => 4, "success:false" => 1}
      }

      assert {:ok, bucket} = Metrics.upsert_bucket(attrs)
      assert bucket.count == 5
      assert bucket.sum_values["duration_ms"] == 500
    end

    test "merges with existing bucket" do
      bucket_start = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs1 = %{
        event_name: "test.merge",
        bucket_type: :minute,
        bucket_start: bucket_start,
        count: 5,
        sum_values: %{"duration_ms" => 500},
        min_values: %{"duration_ms" => 50},
        max_values: %{"duration_ms" => 150},
        metadata_counts: %{}
      }

      attrs2 = %{
        event_name: "test.merge",
        bucket_type: :minute,
        bucket_start: bucket_start,
        count: 3,
        sum_values: %{"duration_ms" => 300},
        min_values: %{"duration_ms" => 40},
        max_values: %{"duration_ms" => 200},
        metadata_counts: %{}
      }

      {:ok, _} = Metrics.upsert_bucket(attrs1)
      {:ok, bucket} = Metrics.upsert_bucket(attrs2)

      # Count should be merged (5 + 3 = 8)
      assert bucket.count == 8
      # Sum should be merged (500 + 300 = 800)
      assert bucket.sum_values["duration_ms"] == 800
      # Min should take lower (min(50, 40) = 40)
      assert bucket.min_values["duration_ms"] == 40
      # Max should take higher (max(150, 200) = 200)
      assert bucket.max_values["duration_ms"] == 200
    end

    test "rejects invalid event_name" do
      attrs = %{
        event_name: "Invalid Name!",
        bucket_type: :minute,
        bucket_start: DateTime.utc_now(),
        count: 1
      }

      assert_raise ArgumentError, fn ->
        Metrics.upsert_bucket(attrs)
      end
    end
  end

  describe "query_buckets/4" do
    test "queries buckets by name, type, and time range" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Metrics.upsert_bucket(%{
          event_name: "test.bucket",
          bucket_type: :hour,
          bucket_start: now,
          count: 10
        })

      from = DateTime.add(now, -60, :second)
      to = DateTime.add(now, 60, :second)

      buckets = Metrics.query_buckets("test.bucket", :hour, from, to)
      assert length(buckets) == 1
      assert hd(buckets).count == 10
    end
  end

  describe "purge_events_before/1" do
    test "deletes old events" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -3600, :second)

      Metrics.insert_events([
        %{event_name: "test.purge", measurements: %{}, metadata: %{}, occurred_at: old}
      ])

      cutoff = DateTime.add(now, -1800, :second)
      {deleted, _} = Metrics.purge_events_before(cutoff)

      assert deleted == 1
    end
  end

  describe "purge_buckets_before/2" do
    test "deletes old buckets of specified type" do
      old = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        Metrics.upsert_bucket(%{
          event_name: "test.purge.bucket",
          bucket_type: :minute,
          bucket_start: old,
          count: 5
        })

      cutoff = DateTime.add(DateTime.utc_now(), -1800, :second)
      {deleted, _} = Metrics.purge_buckets_before(:minute, cutoff)

      assert deleted == 1
    end
  end
end
