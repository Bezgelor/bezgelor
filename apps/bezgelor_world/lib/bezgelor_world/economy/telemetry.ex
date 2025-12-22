defmodule BezgelorWorld.Economy.Telemetry do
  @moduledoc """
  GenServer for collecting and batching economy telemetry events.

  ## Overview

  Subscribes to telemetry events from `BezgelorCore.Economy.TelemetryEvents`
  and batches them for efficient database writes. This reduces database load
  by collecting events in memory and periodically flushing them in bulk.

  ## Metrics Tracking

  In addition to batching events for persistence, this server tracks real-time
  metrics in memory for quick access:
  - Total transaction count by type
  - Total currency flow (in/out) by type
  - Recent transaction rate
  - Event counts by category

  ## Configuration

  The following options can be configured via application config:

      config :bezgelor_world, BezgelorWorld.Economy.Telemetry,
        batch_size: 100,
        flush_interval_ms: 5000

  - `:batch_size` - Flush to database when this many events are batched (default: 100)
  - `:flush_interval_ms` - Flush to database at this interval (default: 5000ms)

  ## Usage

      # Get current metrics summary
      metrics = BezgelorWorld.Economy.Telemetry.get_metrics_summary()

      # Manually flush pending events
      :ok = BezgelorWorld.Economy.Telemetry.flush()
  """

  use GenServer

  alias BezgelorCore.Economy.TelemetryEvents
  alias BezgelorDb.Economy

  require Logger

  @default_batch_size 100
  @default_flush_interval_ms 5000

  @type event_batch :: %{
          measurements: map(),
          metadata: map(),
          timestamp: DateTime.t()
        }

  @type metrics :: %{
          currency_transactions: non_neg_integer(),
          vendor_transactions: non_neg_integer(),
          loot_drops: non_neg_integer(),
          auction_events: non_neg_integer(),
          trade_completions: non_neg_integer(),
          mail_sent: non_neg_integer(),
          crafting_completions: non_neg_integer(),
          repair_completions: non_neg_integer(),
          total_currency_gained: non_neg_integer(),
          total_currency_spent: non_neg_integer(),
          last_flush: DateTime.t() | nil,
          pending_events: non_neg_integer()
        }

  @type state :: %{
          batch: [event_batch()],
          batch_size: non_neg_integer(),
          flush_interval_ms: non_neg_integer(),
          flush_timer: reference() | nil,
          metrics: metrics()
        }

  ## Client API

  @doc """
  Start the Economy Telemetry GenServer.

  ## Options

  - `:batch_size` - Flush when this many events are batched (default: 100)
  - `:flush_interval_ms` - Flush at this interval (default: 5000ms)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attach telemetry handlers for all economy events.

  This is called automatically during init, but can be called manually if needed.
  """
  @spec attach_handlers() :: :ok
  def attach_handlers do
    GenServer.call(__MODULE__, :attach_handlers)
  end

  @doc """
  Get a snapshot of current metrics.

  Returns a map with counts and totals for all economy event types.
  """
  @spec get_metrics_summary() :: metrics()
  def get_metrics_summary do
    GenServer.call(__MODULE__, :get_metrics_summary)
  end

  @doc """
  Manually flush all pending events to the database.

  Returns `:ok` after the flush completes.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Get configuration from opts or application config
    config = Application.get_env(:bezgelor_world, __MODULE__, [])
    batch_size = Keyword.get(opts, :batch_size) || Keyword.get(config, :batch_size, @default_batch_size)
    flush_interval_ms = Keyword.get(opts, :flush_interval_ms) || Keyword.get(config, :flush_interval_ms, @default_flush_interval_ms)

    state = %{
      batch: [],
      batch_size: batch_size,
      flush_interval_ms: flush_interval_ms,
      flush_timer: nil,
      metrics: initial_metrics()
    }

    # Attach telemetry handlers
    :ok = do_attach_handlers()

    # Schedule first flush
    timer = schedule_flush(flush_interval_ms)
    state = %{state | flush_timer: timer}

    Logger.info("Economy.Telemetry started (batch_size: #{batch_size}, flush_interval: #{flush_interval_ms}ms)")
    {:ok, state}
  end

  @impl true
  def handle_call(:attach_handlers, _from, state) do
    :ok = do_attach_handlers()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_metrics_summary, _from, state) do
    metrics = Map.put(state.metrics, :pending_events, length(state.batch))
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    state = do_flush(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    # Periodic flush timer fired
    state = do_flush(state)

    # Schedule next flush
    timer = schedule_flush(state.flush_interval_ms)
    state = %{state | flush_timer: timer}

    {:noreply, state}
  end

  @impl true
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    # Add event to batch
    event = %{
      event_name: event_name,
      measurements: measurements,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    state = %{state | batch: [event | state.batch]}

    # Update metrics
    state = update_metrics(state, event_name, measurements, metadata)

    # Check if we should flush due to batch size
    state =
      if length(state.batch) >= state.batch_size do
        do_flush(state)
      else
        state
      end

    {:noreply, state}
  end

  ## Private Functions

  defp initial_metrics do
    %{
      currency_transactions: 0,
      vendor_transactions: 0,
      loot_drops: 0,
      auction_events: 0,
      trade_completions: 0,
      mail_sent: 0,
      crafting_completions: 0,
      repair_completions: 0,
      total_currency_gained: 0,
      total_currency_spent: 0,
      last_flush: nil,
      pending_events: 0
    }
  end

  defp do_attach_handlers do
    # Attach a handler for each economy telemetry event
    events = TelemetryEvents.event_names()

    Enum.each(events, fn event_name ->
      handler_id = {:economy_telemetry, event_name}

      # Detach if already attached (idempotent)
      :telemetry.detach(handler_id)

      # Attach handler that sends event to this GenServer
      # Note: Must use module-qualified function reference to avoid performance penalty
      :telemetry.attach(
        handler_id,
        event_name,
        &__MODULE__.handle_telemetry_event/4,
        nil
      )
    end)

    :ok
  end

  @doc false
  # Public for module-qualified telemetry handler reference (avoids performance penalty)
  def handle_telemetry_event(event_name, measurements, metadata, _config) do
    # Forward event to GenServer for batching
    send(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush, interval_ms)
  end

  defp do_flush(state) do
    # Always update last_flush to show the flush cycle is running
    state = %{state | metrics: Map.put(state.metrics, :last_flush, DateTime.utc_now())}

    if state.batch == [] do
      # Nothing to flush
      state
    else
      # Reverse batch to get chronological order
      events = Enum.reverse(state.batch)

      # Convert events to database records and insert
      case persist_events(events) do
        {:ok, count} ->
          Logger.debug("Economy.Telemetry flushed #{count} events to database")
          %{state | batch: []}

        {:error, reason} ->
          Logger.error("Economy.Telemetry flush failed: #{inspect(reason)}")
          # Keep events in batch for retry
          state
      end
    end
  end

  defp persist_events(events) do
    # Convert telemetry events to currency transaction records
    transactions =
      events
      |> Enum.filter(&currency_transaction?/1)
      |> Enum.map(&event_to_transaction/1)

    # Batch insert all transactions in a single operation
    Economy.record_transactions_batch(transactions)
  end

  defp currency_transaction?(%{event_name: [:bezgelor, :economy, :currency, :transaction]}), do: true
  defp currency_transaction?(_), do: false

  defp event_to_transaction(%{measurements: measurements, metadata: metadata}) do
    %{
      character_id: metadata.character_id,
      currency_type: currency_type_to_id(metadata.currency_type),
      amount: measurements.amount,
      balance_after: measurements.balance_after,
      source_type: atom_to_string(metadata.source_type),
      source_id: metadata.source_id,
      metadata: %{
        duration_ms: measurements.duration_ms
      }
    }
  end

  defp currency_type_to_id(:credits), do: 1
  defp currency_type_to_id(:omnibits), do: 2
  defp currency_type_to_id(_), do: 0

  defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_to_string(string) when is_binary(string), do: string

  defp update_metrics(state, event_name, measurements, _metadata) do
    metrics = state.metrics

    metrics =
      case event_name do
        [:bezgelor, :economy, :currency, :transaction] ->
          metrics
          |> Map.update!(:currency_transactions, &(&1 + 1))
          |> update_currency_flow(measurements.amount)

        [:bezgelor, :economy, :vendor, :transaction] ->
          Map.update!(metrics, :vendor_transactions, &(&1 + 1))

        [:bezgelor, :economy, :loot, :drop] ->
          metrics
          |> Map.update!(:loot_drops, &(&1 + 1))
          |> update_currency_flow(measurements.currency_amount)

        [:bezgelor, :economy, :auction, :event] ->
          Map.update!(metrics, :auction_events, &(&1 + 1))

        [:bezgelor, :economy, :trade, :complete] ->
          Map.update!(metrics, :trade_completions, &(&1 + 1))

        [:bezgelor, :economy, :mail, :sent] ->
          Map.update!(metrics, :mail_sent, &(&1 + 1))

        [:bezgelor, :economy, :crafting, :complete] ->
          Map.update!(metrics, :crafting_completions, &(&1 + 1))

        [:bezgelor, :economy, :repair, :complete] ->
          Map.update!(metrics, :repair_completions, &(&1 + 1))

        _ ->
          metrics
      end

    %{state | metrics: metrics}
  end

  defp update_currency_flow(metrics, amount) when amount > 0 do
    Map.update!(metrics, :total_currency_gained, &(&1 + amount))
  end

  defp update_currency_flow(metrics, amount) when amount < 0 do
    Map.update!(metrics, :total_currency_spent, &(&1 + abs(amount)))
  end

  defp update_currency_flow(metrics, _amount), do: metrics
end
