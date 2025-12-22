defmodule BezgelorPortal.TelemetryCollectorTest do
  use ExUnit.Case, async: false

  alias BezgelorPortal.TelemetryCollector
  alias BezgelorDb.Repo

  @moduletag :database

  setup do
    # Setup database sandbox
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Start the collector with test configuration
    config = [
      flush_interval: 100,
      max_buffer_size: 5,
      tracked_events: [
        "test.event.one",
        "test.event.two"
      ]
    ]

    Application.put_env(:bezgelor_portal, TelemetryCollector, config)

    # Start collector
    start_supervised!(TelemetryCollector)

    # Ensure buffer is empty
    {:ok, 0} = TelemetryCollector.flush()

    # Clean database for this test
    Repo.delete_all(BezgelorDb.Schema.TelemetryEvent)

    :ok
  end

  describe "telemetry event capture" do
    test "captures tracked telemetry events" do
      # Emit a tracked event
      :telemetry.execute(
        [:test, :event, :one],
        %{count: 1},
        %{account_id: 123, character_id: 456}
      )

      # Wait a bit for async processing
      Process.sleep(10)

      # Check buffer has the event
      assert TelemetryCollector.buffer_size() == 1
    end

    test "ignores untracked telemetry events" do
      # Emit an untracked event
      :telemetry.execute(
        [:test, :event, :untracked],
        %{count: 1},
        %{}
      )

      Process.sleep(10)

      # Buffer should remain empty
      assert TelemetryCollector.buffer_size() == 0
    end

    test "captures multiple events" do
      # Emit multiple events
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      :telemetry.execute([:test, :event, :two], %{count: 2}, %{character_id: 2})
      :telemetry.execute([:test, :event, :one], %{count: 3}, %{zone_id: 3})

      Process.sleep(10)

      assert TelemetryCollector.buffer_size() == 3
    end
  end

  describe "metadata sanitization" do
    test "keeps whitelisted metadata keys" do
      :telemetry.execute(
        [:test, :event, :one],
        %{},
        %{
          account_id: 123,
          character_id: 456,
          zone_id: 789,
          success: true,
          creature_id: 111,
          quest_id: 222,
          item_id: 333,
          spell_id: 444,
          guild_id: 555,
          world_id: 666
        }
      )

      Process.sleep(10)

      # Force flush and verify event was stored
      {:ok, count} = TelemetryCollector.flush()
      assert count == 1
    end

    test "filters out non-whitelisted metadata keys" do
      :telemetry.execute(
        [:test, :event, :one],
        %{},
        %{
          account_id: 123,
          password: "secret",
          email: "test@test.com",
          ip_address: "127.0.0.1",
          session_token: "abc123"
        }
      )

      Process.sleep(10)

      # Force flush to database
      {:ok, count} = TelemetryCollector.flush()
      assert count == 1

      # Query the event back and verify sensitive data was filtered
      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)
      events = BezgelorDb.Metrics.query_events("test.event.one", from, to)

      assert length(events) == 1
      event = List.first(events)

      # Should only have account_id
      assert Map.has_key?(event.metadata, "account_id")
      refute Map.has_key?(event.metadata, "password")
      refute Map.has_key?(event.metadata, "email")
      refute Map.has_key?(event.metadata, "ip_address")
      refute Map.has_key?(event.metadata, "session_token")
    end

    test "handles string keys in metadata" do
      :telemetry.execute(
        [:test, :event, :one],
        %{},
        %{
          "account_id" => 123,
          "character_id" => 456,
          "invalid_key" => "should be filtered"
        }
      )

      Process.sleep(10)

      {:ok, count} = TelemetryCollector.flush()
      assert count == 1

      # Query back and verify
      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)
      events = BezgelorDb.Metrics.query_events("test.event.one", from, to)

      assert length(events) == 1
      event = List.first(events)

      assert Map.has_key?(event.metadata, "account_id")
      assert Map.has_key?(event.metadata, "character_id")
      refute Map.has_key?(event.metadata, "invalid_key")
    end
  end

  describe "buffer flushing" do
    test "flushes buffer on interval" do
      # Emit some events
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      :telemetry.execute([:test, :event, :one], %{count: 2}, %{account_id: 2})

      Process.sleep(10)
      assert TelemetryCollector.buffer_size() == 2

      # Wait for flush interval (100ms in test config)
      Process.sleep(150)

      # Buffer should be empty after flush
      assert TelemetryCollector.buffer_size() == 0
    end

    test "flushes buffer when max size reached" do
      # Max buffer size is 5 in test config
      # Emit 5 events to trigger flush
      for i <- 1..5 do
        :telemetry.execute([:test, :event, :one], %{count: i}, %{account_id: i})
      end

      # Wait for processing
      Process.sleep(50)

      # Buffer should be empty after auto-flush
      assert TelemetryCollector.buffer_size() == 0

      # Verify events were stored
      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)
      events = BezgelorDb.Metrics.query_events("test.event.one", from, to)

      assert length(events) == 5
    end

    test "manual flush clears buffer" do
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      :telemetry.execute([:test, :event, :two], %{count: 2}, %{character_id: 2})

      Process.sleep(10)
      assert TelemetryCollector.buffer_size() == 2

      # Manual flush
      {:ok, count} = TelemetryCollector.flush()
      assert count == 2

      # Buffer should be empty
      assert TelemetryCollector.buffer_size() == 0
    end

    test "handles empty buffer flush gracefully" do
      assert TelemetryCollector.buffer_size() == 0

      {:ok, count} = TelemetryCollector.flush()
      assert count == 0
    end
  end

  describe "event storage" do
    test "stores events with correct structure" do
      :telemetry.execute(
        [:test, :event, :one],
        %{duration: 100, count: 5},
        %{account_id: 999, success: true}
      )

      Process.sleep(10)
      {:ok, count} = TelemetryCollector.flush()
      assert count == 1

      # Query back the event
      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)
      events = BezgelorDb.Metrics.query_events("test.event.one", from, to)

      assert length(events) == 1
      event = List.first(events)

      assert event.event_name == "test.event.one"
      assert event.measurements == %{"duration" => 100, "count" => 5}
      assert event.metadata["account_id"] == 999
      assert event.metadata["success"] == true
    end

    test "stores multiple different events" do
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      :telemetry.execute([:test, :event, :two], %{count: 2}, %{character_id: 2})

      Process.sleep(10)
      {:ok, count} = TelemetryCollector.flush()
      assert count == 2

      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)

      events_one = BezgelorDb.Metrics.query_events("test.event.one", from, to)
      events_two = BezgelorDb.Metrics.query_events("test.event.two", from, to)

      assert length(events_one) == 1
      assert length(events_two) == 1
    end
  end

  describe "process lifecycle" do
    test "flushes remaining events on manual flush before termination" do
      # Add events to buffer
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      :telemetry.execute([:test, :event, :one], %{count: 2}, %{account_id: 2})

      Process.sleep(10)
      assert TelemetryCollector.buffer_size() == 2

      # Manually flush before termination (simulating graceful shutdown)
      {:ok, count} = TelemetryCollector.flush()
      assert count == 2

      # Buffer should be empty
      assert TelemetryCollector.buffer_size() == 0

      # Verify events were stored
      from = DateTime.utc_now() |> DateTime.add(-60, :second)
      to = DateTime.utc_now() |> DateTime.add(60, :second)
      events = BezgelorDb.Metrics.query_events("test.event.one", from, to)

      # Should have at least our 2 events
      assert length(events) >= 2
    end
  end

  describe "handler management" do
    test "detaches handlers on termination" do
      # Get the process
      pid = Process.whereis(TelemetryCollector)
      ref = Process.monitor(pid)

      # Emit event while collector is running
      :telemetry.execute([:test, :event, :one], %{count: 1}, %{account_id: 1})
      Process.sleep(10)

      # Stop the collector (via supervisor stop)
      stop_supervised(TelemetryCollector)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1000 -> flunk("Process did not terminate")
      end

      # Wait a bit for cleanup
      Process.sleep(50)

      # Restart the collector
      start_supervised!(TelemetryCollector)

      # Emit another event - should work with new handlers
      :telemetry.execute([:test, :event, :one], %{count: 2}, %{account_id: 2})
      Process.sleep(10)

      # Should have 1 event in buffer (the new one after restart)
      assert TelemetryCollector.buffer_size() == 1
    end
  end
end
