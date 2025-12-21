# Portal Economy Support - Design Document

**Date:** 2025-12-21
**Status:** Approved

## Overview

Comprehensive economy tracking for the Bezgelor admin portal, providing:
- Transaction logging for all currency changes with drill-down capability
- Real-time analytics dashboard with live updates
- Threshold-based anomaly detection with Discord alerts

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transaction scope | Comprehensive | Track all currency flows: quests, vendors, loot, mail, trades, AH, repairs, taxi, tradeskills, guild bank, housing |
| Data flow | Dual-write | DB transaction for persistence (atomic with currency change), telemetry for real-time display |
| Aggregation | Raw only | Aggregate on-the-fly; PostgreSQL handles millions of rows efficiently |
| Categorization | Typed with metadata | `source` enum + `source_id` for drill-down ("show all gold from quest X") |
| Real-time updates | PubSub + debounce | 5-second batching reduces client updates under load |
| Anomaly detection | Threshold alerts | Configurable rules (e.g., >100k gold/hour), easy to tune and debug |
| Notifications | Dashboard + Discord | Webhook for real-time admin notification |
| Retention | Keep forever | Modest volume for private emulator; optimize later if needed |

## Schema Changes

### New Table: `currency_transactions`

Immutable log of all currency changes.

```elixir
schema "currency_transactions" do
  belongs_to :character, Character
  belongs_to :account, Account  # denormalized for faster queries

  field :currency_type, Ecto.Enum, values: [
    :gold, :elder_gems, :renown, :prestige, :glory,
    :crafting_vouchers, :war_coins, :shade_silver,
    :protostar_promissory_notes
  ]
  field :amount, :integer          # positive = gain, negative = loss
  field :balance_after, :integer   # snapshot for auditing

  # Source tracking with drill-down
  field :source, Ecto.Enum, values: [
    :quest_reward, :vendor_buy, :vendor_sell, :loot_pickup,
    :mail_received, :mail_sent, :trade_received, :trade_sent,
    :auction_sold, :auction_purchased, :auction_fee,
    :repair_cost, :taxi_fee, :tradeskill_cost,
    :guild_deposit, :guild_withdraw, :housing_purchase,
    :admin_grant, :admin_remove, :other
  ]
  field :source_id, :integer       # nullable - quest_id, vendor_id, mail_id, etc.
  field :metadata, :map            # additional context (reason, admin notes, etc.)

  field :session_id, :string       # for grouping transactions in a play session

  timestamps(type: :utc_datetime, updated_at: false)  # immutable log
end
```

**Indexes:**
- `character_id` + `inserted_at` (most common query pattern)
- `source` + `inserted_at` (filter by transaction type)
- `inserted_at` alone (time-range queries for dashboard)

### New Table: `economy_alerts`

Threshold violations for investigation.

```elixir
schema "economy_alerts" do
  belongs_to :character, Character

  field :type, Ecto.Enum, values: [
    :excessive_gold_gain, :high_balance,
    :suspicious_pattern, :rapid_transactions
  ]
  field :details, :map
  field :status, Ecto.Enum, values: [:open, :investigating, :resolved, :dismissed]
  field :resolved_by_id, :integer
  field :resolution_notes, :string

  timestamps(type: :utc_datetime)
end
```

## New Modules

### `BezgelorDb.Economy`

Context module - single entry point for all currency operations.

```elixir
defmodule BezgelorDb.Economy do
  @moduledoc """
  Economy tracking context.

  All currency modifications MUST go through this module to ensure
  transaction logging. Direct updates to CharacterCurrency are prohibited.
  """

  # Core API - wraps existing Inventory.modify_currency
  def modify_currency(character_id, currency_type, amount, source, opts \\ []) do
    source_id = Keyword.get(opts, :source_id)
    metadata = Keyword.get(opts, :metadata, %{})
    session_id = Keyword.get(opts, :session_id)

    Repo.transaction(fn ->
      # 1. Get current balance
      currency = get_or_create_currency(character_id)
      current_balance = Map.get(currency, currency_type, 0)
      new_balance = current_balance + amount

      # 2. Update currency (existing logic)
      {:ok, updated} = do_modify_currency(currency, currency_type, amount)

      # 3. Log transaction (same DB transaction = atomic)
      {:ok, _log} = create_transaction_log(%{
        character_id: character_id,
        account_id: get_account_id(character_id),
        currency_type: currency_type,
        amount: amount,
        balance_after: new_balance,
        source: source,
        source_id: source_id,
        metadata: metadata,
        session_id: session_id
      })

      # 4. Emit telemetry for real-time dashboard
      :telemetry.execute(
        [:bezgelor, :economy, :transaction],
        %{amount: amount, balance: new_balance},
        %{currency: currency_type, source: source, character_id: character_id}
      )

      updated
    end)
  end

  # Query functions for dashboard
  def total_currency_in_circulation(currency_type)
  def sum_transactions(currency_type, date_range, direction)
  def top_currency_holders(currency_type, opts)
  def transactions_by_source(date_range)
  def list_recent_transactions(opts)
  def list_alerts(opts)
  def create_alert(attrs)
end
```

### `BezgelorWorld.Economy.Telemetry`

Handles telemetry events, debouncing, and PubSub broadcasting.

```elixir
defmodule BezgelorWorld.Economy.Telemetry do
  use GenServer

  @debounce_interval 5_000  # 5 seconds
  @pubsub BezgelorPortal.PubSub
  @topic "economy:updates"

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_) do
    :telemetry.attach(
      "economy-transaction-handler",
      [:bezgelor, :economy, :transaction],
      &handle_transaction/4,
      nil
    )

    schedule_flush()
    {:ok, %{buffer: [], last_flush: System.monotonic_time(:millisecond)}}
  end

  # Telemetry callback - buffers transactions
  defp handle_transaction(_event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:transaction, measurements, metadata})
  end

  def handle_cast({:transaction, measurements, metadata}, state) do
    entry = Map.merge(measurements, metadata) |> Map.put(:timestamp, DateTime.utc_now())
    {:noreply, %{state | buffer: [entry | state.buffer]}}
  end

  def handle_info(:flush, state) do
    if state.buffer != [] do
      summary = aggregate_buffer(state.buffer)
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:economy_update, summary})
    end

    schedule_flush()
    {:noreply, %{state | buffer: [], last_flush: System.monotonic_time(:millisecond)}}
  end

  defp aggregate_buffer(transactions) do
    %{
      transaction_count: length(transactions),
      by_currency: Enum.group_by(transactions, & &1.currency) |> summarize_groups(),
      by_source: Enum.group_by(transactions, & &1.source) |> summarize_groups(),
      recent: Enum.take(transactions, 10)
    }
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @debounce_interval)
end
```

### `BezgelorWorld.Economy.Alerts`

Threshold-based detection with Discord webhook integration.

```elixir
defmodule BezgelorWorld.Economy.Alerts do
  use GenServer

  @default_thresholds %{
    gold_gain_per_hour: 100_000,
    gold_balance_max: 1_000_000,
    transactions_per_minute: 60
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_) do
    :telemetry.attach(
      "economy-alert-handler",
      [:bezgelor, :economy, :transaction],
      &check_transaction/4,
      nil
    )

    :timer.send_interval(60_000, :check_balances)
    {:ok, %{hourly_gains: %{}, minute_counts: %{}}}
  end

  defp check_transaction(_event, %{amount: amount}, %{character_id: cid} = meta, _) when amount > 0 do
    GenServer.cast(__MODULE__, {:record_gain, cid, amount, meta})
  end
  defp check_transaction(_, _, _, _), do: :ok

  def handle_cast({:record_gain, character_id, amount, meta}, state) do
    key = {character_id, current_hour()}
    current = Map.get(state.hourly_gains, key, 0)
    new_total = current + amount

    threshold = get_threshold(:gold_gain_per_hour)
    if new_total > threshold and current <= threshold do
      trigger_alert(:excessive_gold_gain, %{
        character_id: character_id,
        amount: new_total,
        threshold: threshold,
        source: meta.source
      })
    end

    {:noreply, put_in(state.hourly_gains[key], new_total)}
  end

  defp trigger_alert(type, details) do
    # 1. Log to database
    Economy.create_alert(%{type: type, details: details, status: :open})

    # 2. Broadcast to dashboard
    Phoenix.PubSub.broadcast(BezgelorPortal.PubSub, "economy:alerts", {:new_alert, type, details})

    # 3. Send Discord webhook
    send_discord_alert(type, details)
  end

  defp send_discord_alert(type, details) do
    webhook_url = Application.get_env(:bezgelor_world, :discord_economy_webhook)
    if webhook_url do
      payload = format_discord_embed(type, details)
      Task.start(fn ->
        HTTPoison.post(webhook_url, Jason.encode!(payload), [{"Content-Type", "application/json"}])
      end)
    end
  end
end
```

## Dashboard Updates

Replace placeholder `BezgelorPortalWeb.Admin.EconomyLive` with real functionality:

**Overview Tab:**
- Total gold in circulation (sum of all character balances)
- Daily gold generated/removed with breakdown by source
- Pie chart of gold sources (quests, loot, vendors, etc.)
- Top 10 gold holders

**Transactions Tab:**
- Searchable/filterable transaction log
- Filters: character name, source type, date range, amount range
- Export to CSV

**Alerts Tab:**
- Open alerts with character details
- Actions: Investigate, Resolve, Dismiss
- Resolution notes field
- Alert history

**Live Feed (sidebar):**
- Real-time transaction stream (debounced 5s)
- Shows last ~10 transactions with source and amount

## Telemetry Metrics

Add to `BezgelorPortalWeb.Telemetry`:

```elixir
counter("bezgelor.economy.transaction.count",
  tags: [:currency_type, :source],
  description: "Total currency transactions"
),
sum("bezgelor.economy.transaction.amount",
  tags: [:currency_type, :source],
  description: "Sum of currency amounts (can be negative)"
),
last_value("bezgelor.economy.circulation.total",
  tags: [:currency_type],
  description: "Total currency in circulation"
),
counter("bezgelor.economy.alert.triggered",
  tags: [:type],
  description: "Economy alerts triggered"
)
```

## Configuration

Add to `config/config.exs`:

```elixir
config :bezgelor_world, :economy,
  gold_gain_per_hour_threshold: 100_000,
  gold_balance_max_threshold: 1_000_000,
  transactions_per_minute_threshold: 60,
  discord_webhook_url: System.get_env("ECONOMY_DISCORD_WEBHOOK"),
  dashboard_update_interval_ms: 5_000
```

Thresholds are runtime-configurable via Admin > Settings > Economy.

## Migration Path

### Callers to Update

| Location | Current | After |
|----------|---------|-------|
| `quest/reward_handler.ex` | `Inventory.modify_currency(char_id, :gold, amount)` | `Economy.modify_currency(char_id, :gold, amount, :quest_reward, source_id: quest_id)` |
| `handler/vendor_handler.ex` | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :vendor_buy, source_id: vendor_id)` |
| `handler/vendor_sell_handler.ex` | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :vendor_sell, source_id: vendor_id)` |
| `handler/loot_handler.ex` | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :loot_pickup, source_id: creature_id)` |
| `handler/mail_handler.ex` | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :mail_received, source_id: mail_id)` |
| `handler/tradeskill_handler.ex` | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :tradeskill_cost, source_id: schematic_id)` |
| `portal.ex` (admin grants) | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :admin_grant, metadata: %{reason: reason})` |
| `economy_live.ex` (admin gifts) | `Inventory.modify_currency(...)` | `Economy.modify_currency(..., :admin_grant, metadata: %{reason: reason})` |

### Deprecation Strategy

1. Add `Economy.modify_currency/5` with full logging
2. Update `Inventory.modify_currency/3` to log a warning + delegate to Economy with `:other` source
3. Migrate all callers one by one
4. Remove `Inventory.modify_currency/3` once all callers migrated

## Files to Create/Modify

### New Files
- `apps/bezgelor_db/lib/bezgelor_db/schema/currency_transaction.ex`
- `apps/bezgelor_db/lib/bezgelor_db/schema/economy_alert.ex`
- `apps/bezgelor_db/lib/bezgelor_db/economy.ex`
- `apps/bezgelor_db/priv/repo/migrations/YYYYMMDD_create_economy_tables.exs`
- `apps/bezgelor_world/lib/bezgelor_world/economy/telemetry.ex`
- `apps/bezgelor_world/lib/bezgelor_world/economy/alerts.ex`

### Modified Files
- `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/economy_live.ex` (replace placeholder)
- `apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex` (add economy metrics)
- `apps/bezgelor_world/lib/bezgelor_world/application.ex` (start Economy.Telemetry, Economy.Alerts)
- `config/config.exs` (add economy config)
- ~8 handler files (migrate to Economy.modify_currency/5)

## Testing Strategy

- Unit tests for `Economy` context functions
- Unit tests for alert threshold logic
- Integration test: currency modification → transaction logged → telemetry emitted
- LiveView tests for dashboard functionality
