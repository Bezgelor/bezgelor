defmodule Mix.Tasks.Bezgelor.Telemetry.DiscoverTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Bezgelor.Telemetry.Discover

  describe "extract_events_from_module/1" do
    test "extracts @telemetry_events from module with telemetry_events/0 function" do
      defmodule TestModuleWithEvents do
        @telemetry_events [
          %{
            event: [:test, :event],
            measurements: [:count],
            tags: [:tag1],
            description: "Test event",
            domain: :test
          }
        ]

        def telemetry_events, do: @telemetry_events
      end

      events = Discover.extract_events_from_module(TestModuleWithEvents)
      assert length(events) == 1
      assert hd(events).event == [:test, :event]
    end

    test "returns empty list for module without events" do
      defmodule TestModuleWithoutEvents do
        def some_function, do: :ok
      end

      events = Discover.extract_events_from_module(TestModuleWithoutEvents)
      assert events == []
    end

    test "extracts multiple events from module" do
      defmodule TestModuleMultipleEvents do
        @telemetry_events [
          %{
            event: [:test, :first],
            measurements: [:count],
            tags: [],
            description: "First event",
            domain: :test
          },
          %{
            event: [:test, :second],
            measurements: [:duration],
            tags: [:id],
            description: "Second event",
            domain: :test
          }
        ]

        def telemetry_events, do: @telemetry_events
      end

      events = Discover.extract_events_from_module(TestModuleMultipleEvents)
      assert length(events) == 2
    end
  end
end
