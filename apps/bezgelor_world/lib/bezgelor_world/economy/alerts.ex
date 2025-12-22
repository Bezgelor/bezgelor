defmodule BezgelorWorld.Economy.Alerts do
  @moduledoc """
  GenServer for managing economy alerts and detecting suspicious activity.

  ## Overview

  Monitors economic activity patterns and automatically generates alerts based
  on configurable thresholds. Provides real-time checking functions and caches
  recent alerts for quick access.

  ## Features

  - High-value transaction detection
  - Rapid transaction pattern monitoring
  - Recent alert caching for performance
  - Configurable thresholds
  - Integration with BezgelorDb.Economy

  ## Usage

      # Check for high-value transaction
      Alerts.check_high_value_transaction(character_id, 1_000_000, 500_000)

      # Check for rapid transactions
      Alerts.check_rapid_transactions(character_id, 50, 300)

      # Get recent alerts
      alerts = Alerts.get_recent_alerts(20)

      # Clear the cache
      Alerts.clear_cache()
  """

  use GenServer

  alias BezgelorDb.Economy

  require Logger

  @type state :: %{
          cache: [map()],
          config: map()
        }

  # Default configuration
  @default_cache_size 100
  @default_high_value_threshold 1_000_000
  @default_rapid_transaction_count 20
  @default_rapid_transaction_timeframe 300

  ## Client API

  @doc "Start the Economy.Alerts GenServer."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a transaction exceeds the high-value threshold and create an alert if needed.

  ## Parameters

  - `character_id` - The character making the transaction
  - `amount` - The transaction amount (absolute value)
  - `threshold` - The threshold to check against (optional, uses config default if not provided)

  ## Returns

  - `{:ok, alert}` if an alert was created
  - `{:ok, :below_threshold}` if no alert needed
  - `{:error, reason}` on failure

  ## Example

      # Check if transaction of 1.5M exceeds 500K threshold
      {:ok, alert} = Alerts.check_high_value_transaction(123, 1_500_000, 500_000)
  """
  @spec check_high_value_transaction(integer(), integer(), integer() | nil) ::
          {:ok, map()} | {:ok, :below_threshold} | {:error, term()}
  def check_high_value_transaction(character_id, amount, threshold \\ nil) do
    GenServer.call(__MODULE__, {:check_high_value, character_id, amount, threshold})
  end

  @doc """
  Check if a character has made too many transactions in a timeframe and create an alert if needed.

  ## Parameters

  - `character_id` - The character to check
  - `count` - The number of transactions to check against
  - `timeframe_seconds` - The timeframe in seconds (optional, uses config default if not provided)

  ## Returns

  - `{:ok, alert}` if an alert was created
  - `{:ok, :below_threshold}` if no alert needed
  - `{:error, reason}` on failure

  ## Example

      # Check if character made more than 50 transactions in last 5 minutes (300 seconds)
      {:ok, alert} = Alerts.check_rapid_transactions(123, 50, 300)
  """
  @spec check_rapid_transactions(integer(), integer(), integer() | nil) ::
          {:ok, map()} | {:ok, :below_threshold} | {:error, term()}
  def check_rapid_transactions(character_id, count, timeframe_seconds \\ nil) do
    GenServer.call(__MODULE__, {:check_rapid_transactions, character_id, count, timeframe_seconds})
  end

  @doc """
  Get recent alerts from the cache.

  ## Parameters

  - `limit` - Maximum number of alerts to return (default: 10)

  ## Returns

  List of alert maps ordered by most recent first.

  ## Example

      alerts = Alerts.get_recent_alerts(20)
  """
  @spec get_recent_alerts(integer()) :: [map()]
  def get_recent_alerts(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_recent_alerts, limit})
  end

  @doc """
  Clear the alert cache and reload from database.

  ## Returns

  `:ok`

  ## Example

      Alerts.clear_cache()
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    config = %{
      cache_size: Keyword.get(opts, :cache_size, @default_cache_size),
      high_value_threshold:
        Keyword.get(opts, :high_value_threshold, @default_high_value_threshold),
      rapid_transaction_count:
        Keyword.get(opts, :rapid_transaction_count, @default_rapid_transaction_count),
      rapid_transaction_timeframe:
        Keyword.get(opts, :rapid_transaction_timeframe, @default_rapid_transaction_timeframe)
    }

    state = %{
      cache: load_cache(config.cache_size),
      config: config
    }

    Logger.info("Economy.Alerts started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_high_value, character_id, amount, threshold}, _from, state) do
    threshold = threshold || state.config.high_value_threshold
    abs_amount = abs(amount)

    if abs_amount >= threshold do
      case create_high_value_alert(character_id, abs_amount, threshold) do
        {:ok, alert} ->
          # Add to cache
          state = add_to_cache(state, alert)
          {:reply, {:ok, alert}, state}

        {:error, reason} = error ->
          Logger.error("Failed to create high-value alert: #{inspect(reason)}")
          {:reply, error, state}
      end
    else
      {:reply, {:ok, :below_threshold}, state}
    end
  end

  @impl true
  def handle_call(
        {:check_rapid_transactions, character_id, count, timeframe_seconds},
        _from,
        state
      ) do
    timeframe = timeframe_seconds || state.config.rapid_transaction_timeframe
    since = DateTime.add(DateTime.utc_now(), -timeframe, :second)

    # Get all transactions in the timeframe
    transactions = Economy.get_transactions_for_character(character_id, since: since, limit: 1000)
    transaction_count = length(transactions)

    if transaction_count >= count do
      case create_rapid_transactions_alert(character_id, transaction_count, timeframe) do
        {:ok, alert} ->
          # Add to cache
          state = add_to_cache(state, alert)
          {:reply, {:ok, alert}, state}

        {:error, reason} = error ->
          Logger.error("Failed to create rapid transactions alert: #{inspect(reason)}")
          {:reply, error, state}
      end
    else
      {:reply, {:ok, :below_threshold}, state}
    end
  end

  @impl true
  def handle_call({:get_recent_alerts, limit}, _from, state) do
    alerts = Enum.take(state.cache, limit)
    {:reply, alerts, state}
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    cache = load_cache(state.config.cache_size)
    state = %{state | cache: cache}
    Logger.info("Economy.Alerts cache cleared and reloaded")
    {:reply, :ok, state}
  end

  ## Private Functions

  defp load_cache(limit) do
    # Load most recent alerts from database
    alerts =
      Economy.list_alerts(limit: limit, preload_character: false)
      |> Enum.map(&alert_to_map/1)

    Logger.debug("Loaded #{length(alerts)} alerts into cache")
    alerts
  end

  defp add_to_cache(state, alert) do
    # Add to front of cache and trim to size
    cache = [alert_to_map(alert) | state.cache]
    cache = Enum.take(cache, state.config.cache_size)
    %{state | cache: cache}
  end

  defp alert_to_map(%BezgelorDb.Schema.EconomyAlert{} = alert) do
    %{
      id: alert.id,
      alert_type: alert.alert_type,
      severity: alert.severity,
      character_id: alert.character_id,
      description: alert.description,
      data: alert.data,
      acknowledged: alert.acknowledged,
      acknowledged_by: alert.acknowledged_by,
      acknowledged_at: alert.acknowledged_at,
      inserted_at: alert.inserted_at
    }
  end

  defp alert_to_map(map) when is_map(map), do: map

  defp create_high_value_alert(character_id, amount, threshold) do
    Economy.create_alert(%{
      alert_type: "high_value_trade",
      severity: determine_severity(amount, threshold),
      character_id: character_id,
      description:
        "High-value transaction detected: #{format_currency(amount)} (threshold: #{format_currency(threshold)})",
      data: %{
        amount: amount,
        threshold: threshold,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    })
  end

  defp create_rapid_transactions_alert(character_id, count, timeframe) do
    Economy.create_alert(%{
      alert_type: "rapid_transactions",
      severity: determine_rapid_severity(count, timeframe),
      character_id: character_id,
      description:
        "Rapid transaction pattern detected: #{count} transactions in #{timeframe} seconds",
      data: %{
        transaction_count: count,
        timeframe_seconds: timeframe,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    })
  end

  defp determine_severity(amount, threshold) do
    ratio = amount / threshold

    cond do
      ratio >= 10.0 -> "critical"
      ratio >= 3.0 -> "warning"
      true -> "info"
    end
  end

  defp determine_rapid_severity(count, _timeframe) do
    cond do
      count >= 100 -> "critical"
      count >= 50 -> "warning"
      true -> "info"
    end
  end

  defp format_currency(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
