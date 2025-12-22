defmodule BezgelorWorld.Economy.AlertsTest do
  use ExUnit.Case, async: false

  @moduletag :database

  alias BezgelorWorld.Economy.Alerts

  setup do
    # Start the Alerts GenServer if not already started
    case GenServer.whereis(Alerts) do
      nil ->
        {:ok, pid} = Alerts.start_link()
        on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      _pid ->
        :ok
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer with default configuration" do
      # The setup already starts it, verify it's running
      assert Process.whereis(Alerts) != nil
    end

    test "starts with custom configuration" do
      opts = [
        cache_size: 50,
        high_value_threshold: 500_000,
        rapid_transaction_count: 30,
        rapid_transaction_timeframe: 600
      ]

      # Start with a different name to avoid conflict
      {:ok, pid} = GenServer.start_link(Alerts, opts)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "check_high_value_transaction/3" do
    test "returns :below_threshold when amount is below threshold" do
      result = Alerts.check_high_value_transaction(999, 100_000, 500_000)
      assert result == {:ok, :below_threshold}
    end

    test "uses default threshold when not provided" do
      # Default is 1_000_000, so 500_000 should be below
      result = Alerts.check_high_value_transaction(999, 500_000)
      assert result == {:ok, :below_threshold}
    end
  end

  describe "check_rapid_transactions/3" do
    test "returns :below_threshold when transaction count is below limit" do
      # Assuming character doesn't have that many transactions
      result = Alerts.check_rapid_transactions(999, 100, 300)
      assert result == {:ok, :below_threshold}
    end
  end

  describe "get_recent_alerts/1" do
    test "returns list of alerts" do
      alerts = Alerts.get_recent_alerts(10)
      assert is_list(alerts)
    end

    test "respects limit parameter" do
      alerts = Alerts.get_recent_alerts(5)
      assert is_list(alerts)
      assert length(alerts) <= 5
    end
  end

  describe "clear_cache/0" do
    test "clears and reloads the cache" do
      result = Alerts.clear_cache()
      assert result == :ok
    end
  end
end
